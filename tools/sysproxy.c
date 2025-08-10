// Minimal persistent sysproxy for Linux x86_64
// Reads JSON lines on stdin; writes JSON responses to stdout.
// Ops: listen, accept, read, write, close.
// NOTE: naive JSON parsing for the specific fields we use.

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>

static void set_line_buffering(void){ setvbuf(stdout, NULL, _IOLBF, 0); }
static void ignore_sigpipe(void){ struct sigaction sa={0}; sa.sa_handler=SIG_IGN; sigaction(SIGPIPE,&sa,NULL); }

static void small_sleep_ms(int ms){
  struct timespec ts;
  ts.tv_sec = ms/1000;
  ts.tv_nsec = (ms%1000)*1000000L;
  nanosleep(&ts, NULL);
}

static long jget_long(const char *s, const char *key, long defv){
  char pat[128]; snprintf(pat,sizeof(pat),"\"%s\"",key);
  const char *p = strstr(s, pat); if(!p) return defv;
  p = strchr(p, ':'); if(!p) return defv; p++;
  while(*p==' '||*p=='\t') p++;
  char *endp=NULL; long v=strtol(p,&endp,10);
  if(endp==p) return defv; return v;
}
static int jget_string(const char *s, const char *key, char *out, size_t outsz){
  char pat[128]; snprintf(pat,sizeof(pat),"\"%s\"",key);
  const char *p=strstr(s, pat); if(!p) return 0;
  p=strchr(p,':'); if(!p) return 0; p++;
  while(*p==' '||*p=='\t') p++;
  if(*p!='"') return 0; p++;
  size_t i=0;
  while(*p && *p!='"' && i+1<outsz){
    if(*p=='\\' && p[1]){ p++; char c=*p++;
      if(c=='n') out[i++]='\n';
      else if(c=='r') out[i++]='\r';
      else if(c=='t') out[i++]='\t';
      else out[i++]=c;
    } else out[i++]=*p++;
  }
  out[i]=0; return 1;
}
static void json_escape_print(const char *b, ssize_t n){
  for(ssize_t i=0;i<n;i++){
    unsigned char c=b[i];
    if(c=='\\') fputs("\\\\",stdout);
    else if(c=='"') fputs("\\\"",stdout);
    else if(c=='\n') fputs("\\n",stdout);
    else if(c=='\r') fputs("\\r",stdout);
    else if(c=='\t') fputs("\\t",stdout);
    else if(c>=0x20 && c<0x7f) fputc(c,stdout);
    else fprintf(stdout,"\\u%04x",c);
  }
}
static void respond_err(long id, const char *msg){
  fprintf(stdout, "{\"id\":%ld,\"ok\":false,\"errno\":%d,\"error\":\"%s\"}\n",
          id, errno, msg?msg:strerror(errno));
  fprintf(stderr, "[sysproxy] ERR id=%ld errno=%d (%s) msg=%s\n",
          id, errno, strerror(errno), msg?msg:"");
}

// Main request processing loop
static void process_requests(void) {
  fprintf(stderr,"[sysproxy] PID=%d starting, stdin/stdout ready\n", getpid());

  // NEW: keep stdin FIFO from hitting EOF by holding a writer FD open
  int keepfd = -1;
  const char *fifo_in_path = getenv("SYSFIFO_IN");
  const char *keep_on = getenv("SYSFIFO_IN_KEEP");
  if (fifo_in_path && keep_on && strcmp(keep_on,"1")==0) {
    keepfd = open(fifo_in_path, O_WRONLY | O_CLOEXEC);
    if (keepfd < 0) {
      fprintf(stderr,"[sysproxy] keep-open failed on %s: %s\n",
              fifo_in_path, strerror(errno));
    } else {
      fprintf(stderr,"[sysproxy] keep-open fd=%d on %s\n", keepfd, fifo_in_path);
    }
  }

  char line[131072];
  for (;;) {
    if (!fgets(line, sizeof(line), stdin)) {
      if (feof(stdin)) {
        clearerr(stdin);
        // For TCP connections, return when EOF is encountered
        if (getenv("SYSPROXY_TCP")) {
          fprintf(stderr, "[sysproxy] TCP connection closed, returning to accept loop\n");
          return;
        }
        small_sleep_ms(200);  // wait for next writer; don't exit (for FIFO mode)
        continue;
      }
      if (ferror(stdin)) {
        clearerr(stdin);
        // For TCP connections, return when error is encountered
        if (getenv("SYSPROXY_TCP")) {
          fprintf(stderr, "[sysproxy] TCP connection error, returning to accept loop\n");
          return;
        }
        small_sleep_ms(200);
        continue;
      }
    } else {
      long id=jget_long(line,"id",0);
      char op[32]; op[0]=0;
      if(!jget_string(line,"op",op,sizeof(op))){ respond_err(id,"bad_op"); continue; }

      if(strcmp(op,"listen")==0){
        char host[64]="0.0.0.0";
        jget_string(line,"host",host,sizeof(host));
        long port=jget_long(line,"port",0);
        long backlog=jget_long(line,"backlog",128);

        int fd=socket(AF_INET,SOCK_STREAM,0);
        if(fd<0){ respond_err(id,"socket"); continue; }

        int on=1; setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&on,sizeof(on));
#ifdef SO_REUSEPORT
        setsockopt(fd,SOL_SOCKET,SO_REUSEPORT,&on,sizeof(on));
#endif

        struct sockaddr_in sa; memset(&sa,0,sizeof(sa));
        sa.sin_family=AF_INET;
        sa.sin_port = htons((unsigned short)port);
        if(strcmp(host,"0.0.0.0")==0 || host[0]==0) sa.sin_addr.s_addr=htonl(INADDR_ANY);
        else {
          if(inet_pton(AF_INET,host,&sa.sin_addr)!=1){
            int e=errno; close(fd); errno=e; respond_err(id,"inet_pton"); continue;
          }
        }

        if(bind(fd,(struct sockaddr*)&sa,sizeof(sa))<0){
          int e=errno; close(fd); errno=e; respond_err(id,"bind"); continue;
        }
        if(listen(fd,(int)backlog)<0){
          int e=errno; close(fd); errno=e; respond_err(id,"listen"); continue;
        }

        // Verify via getsockname
        struct sockaddr_in q; socklen_t ql=sizeof(q); memset(&q,0,sizeof(q));
        if(getsockname(fd,(struct sockaddr*)&q,&ql)==0){
          char addr[64]; inet_ntop(AF_INET,&q.sin_addr,addr,sizeof(addr));
          fprintf(stderr,"[sysproxy] LISTEN fd=%d on %s:%u backlog=%ld\n",
                  fd, addr, (unsigned)ntohs(q.sin_port), backlog);
        } else {
          fprintf(stderr,"[sysproxy] LISTEN fd=%d (getsockname failed: %s)\n", fd, strerror(errno));
        }

        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"fd\":%d}\n",id,fd);
      }
      else if(strcmp(op,"accept")==0){
        long sfd=jget_long(line,"socket",-1);
        struct sockaddr_in ca; socklen_t calen=sizeof(ca);
        int cfd=accept((int)sfd,(struct sockaddr*)&ca,&calen);
        if(cfd<0){ respond_err(id,"accept"); continue; }
        char addr[64]; inet_ntop(AF_INET,&ca.sin_addr,addr,sizeof(addr));
        fprintf(stderr,"[sysproxy] ACCEPT sfd=%ld -> cfd=%d from %s:%u\n",
                sfd, cfd, addr, (unsigned)ntohs(ca.sin_port));
        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"conn\":%d}\n",id,cfd);
      }
      else if(strcmp(op,"read")==0){
        long fd=jget_long(line,"fd",-1);
        long max=jget_long(line,"max",65536);
        if(max<1 || max>4*1024*1024) max=65536;
        char *buf=(char*)malloc((size_t)max);
        if(!buf){ respond_err(id,"oom"); continue; }
        ssize_t n=read((int)fd,buf,(size_t)max);
        if(n<0){ int e=errno; free(buf); errno=e; respond_err(id,"read"); continue; }
        fprintf(stderr,"[sysproxy] READ fd=%ld -> %zd bytes\n", fd, n);
        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"n\":%zd,\"data\":\"",id,n);
        if(n>0) json_escape_print(buf,n);
        fputs("\"}\n",stdout);
        free(buf);
      }
      else if(strcmp(op,"write")==0){
        long fd=jget_long(line,"fd",-1);
        char data[65536]; data[0]=0;
        if(!jget_string(line,"data",data,sizeof(data))){ respond_err(id,"no_data"); continue; }
        size_t len=strlen(data);
        ssize_t n=write((int)fd,data,len);
        if(n<0){ respond_err(id,"write"); continue; }
        fprintf(stderr,"[sysproxy] WRITE fd=%ld <- %zd bytes\n", fd, n);
        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"written\":%zd}\n",id,n);
      }
      else if(strcmp(op,"close")==0){
        long fd=jget_long(line,"fd",-1);
        int rc=close((int)fd);
        if(rc<0){ respond_err(id,"close"); continue; }
        fprintf(stderr,"[sysproxy] CLOSE fd=%ld ok\n", fd);
        fprintf(stdout,"{\"id\":%ld,\"ok\":true}\n",id);
      }
      else if(strcmp(op,"stats")==0){
        fprintf(stderr,"[sysproxy] STATS pid=%d\n", getpid());
        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"pid\":%d}\n", id, getpid());
      }
      else if(strcmp(op,"keepalive")==0){
        // Keep the proxy running without doing anything
        fprintf(stderr,"[sysproxy] KEEPALIVE pid=%d\n", getpid());
        fprintf(stdout,"{\"id\":%ld,\"ok\":true,\"pid\":%d}\n", id, getpid());
      }
      else {
        respond_err(id,"unknown_op");
      }
    }
  }
}

int main(int argc, char** argv){
  set_line_buffering();
  ignore_sigpipe();
  
  const char* ctrl = getenv("SYSPROXY_TCP"); // e.g. "127.0.0.1:9099"
  if (!ctrl && argc >= 3 && strcmp(argv[1],"--ctrl")==0) ctrl = argv[2];

  if (ctrl) {
    char host[64] = {0};
    int  port = 0;
    const char* colon = strchr(ctrl, ':');
    if (colon) {
      size_t len = (size_t)(colon - ctrl);
      if (len >= sizeof(host)) len = sizeof(host) - 1;
      memcpy(host, ctrl, len);
      port = atoi(colon + 1);
    } else {
      strcpy(host, "127.0.0.1");
      port = atoi(ctrl);
    }

    int s = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, host, &a.sin_addr);

    if (bind(s, (struct sockaddr*)&a, sizeof(a)) < 0) { perror("ctrl bind"); exit(1); }
    if (listen(s, 8) < 0) { perror("ctrl listen"); exit(1); }
    fprintf(stderr, "[sysproxy] ctrl listening on %s:%d\n", host, port);
    fflush(stderr);

    for (;;) {
      int c = accept(s, NULL, NULL);
      if (c < 0) { if (errno == EINTR) continue; perror("ctrl accept"); exit(1); }

      // Map stdin/stdout to the accepted socket for the existing main loop.
      int saved_in  = dup(0);
      int saved_out = dup(1);
      dup2(c, 0);
      dup2(c, 1);
      close(c);

      // Process requests on this connection
      process_requests();
      
      // Restore original stdin/stdout and go back to accept
      fflush(stdout);
      dup2(saved_in, 0);
      dup2(saved_out, 1);
      close(saved_in);
      close(saved_out);
      // go back to accept() and keep the HTTP listen fds alive
    }
    return 0;
  }
  
  // Original stdin/stdout mode (for backward compatibility)
  process_requests();
  return 0;
}
