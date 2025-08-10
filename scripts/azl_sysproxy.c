// gcc -O2 -Wall -o .azl/sysproxy scripts/azl_sysproxy.c
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

// Simple NDJSON protocol via stdin/stdout.
// Requests:
//   {"id":N,"op":"listen","host":"0.0.0.0","port":8080,"backlog":128}
//   {"id":N,"op":"accept","lfd":3}
//   {"id":N,"op":"read","fd":5,"max":65536}
//   {"id":N,"op":"write","fd":5,"data": "<raw http response text>"}
//   {"id":N,"op":"close","fd":5}
//
// Responses:
//   {"id":N,"ok":true,"lfd":3} / {"id":N,"ok":true,"fd":5} / {"id":N,"ok":true,"data":"..."}
//   {"id":N,"ok":false,"err":errno,"msg":"..."}

static void println(const char *s){ fputs(s, stdout); fputc('\n', stdout); fflush(stdout); }

static void jerr(long id, const char* msg){
  char buf[512];
  snprintf(buf,sizeof(buf),"{\"id\":%ld,\"ok\":false,\"err\":%d,\"msg\":\"%s\"}",id,errno,msg?msg:"");
  println(buf);
}

static char* jget(const char* line, const char* key, char* out, size_t outsz){
  // super tiny "extract string value": looks for "key":"value"
  // not robust JSON; fine for our controlled messages.
  char pat[64]; snprintf(pat,sizeof(pat),"\"%s\":\"",key);
  char* p = strstr((char*)line, pat);
  if(!p) return NULL;
  p += strlen(pat);
  char* q = strchr(p,'"'); if(!q) return NULL;
  size_t n = (size_t)(q-p); if(n >= outsz) n = outsz-1;
  memcpy(out,p,n); out[n]=0; return out;
}

static long jgetnum(const char* line, const char* key, long defv){
  char pat[64]; snprintf(pat,sizeof(pat),"\"%s\":",key);
  char* p = strstr((char*)line, pat);
  if(!p) return defv;
  p += strlen(pat);
  return strtol(p,NULL,10);
}

int main(void){
  signal(SIGPIPE, SIG_IGN);
  setvbuf(stdin, NULL, _IOLBF, 0);
  setvbuf(stdout, NULL, _IOLBF, 0);

  char line[131072];
  while (fgets(line, sizeof(line), stdin)) {
    // trim
    size_t L = strlen(line);
    while (L && (line[L-1]=='\n' || line[L-1]=='\r')) line[--L]=0;

    long id = jgetnum(line,"id",-1);
    char op[32]; if(!jget(line,"op",op,sizeof(op))){ jerr(id,"bad op"); continue; }

    if(!strcmp(op,"listen")){
      char host[64]; if(!jget(line,"host",host,sizeof(host))){ strcpy(host,"0.0.0.0"); }
      int port = (int)jgetnum(line,"port",8080);
      int backlog = (int)jgetnum(line,"backlog",128);

      int s = socket(AF_INET, SOCK_STREAM, 0);
      if(s<0){ jerr(id,"socket"); continue; }
      int one=1; setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));

      struct sockaddr_in sa; memset(&sa,0,sizeof(sa));
      sa.sin_family = AF_INET;
      sa.sin_port = htons((uint16_t)port);
      if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) { close(s); jerr(id,"inet_pton"); continue; }

      if(bind(s,(struct sockaddr*)&sa,sizeof(sa))<0){ int e=errno; close(s); errno=e; jerr(id,"bind"); continue; }
      if(listen(s,backlog)<0){ int e=errno; close(s); errno=e; jerr(id,"listen"); continue; }

      char resp[256];
      snprintf(resp,sizeof(resp),"{\"id\":%ld,\"ok\":true,\"lfd\":%d}",id,s);
      println(resp);

    } else if(!strcmp(op,"accept")){
      int lfd = (int)jgetnum(line,"lfd",-1);
      if(lfd<0){ jerr(id,"bad lfd"); continue; }
      int c = accept(lfd,NULL,NULL);
      if(c<0){ jerr(id,"accept"); continue; }
      char resp[128];
      snprintf(resp,sizeof(resp),"{\"id\":%ld,\"ok\":true,\"fd\":%d}",id,c);
      println(resp);

    } else if(!strcmp(op,"read")){
      int fd = (int)jgetnum(line,"fd",-1);
      int max = (int)jgetnum(line,"max",65536);
      if(fd<0){ jerr(id,"bad fd"); continue; }
      if(max<=0 || max> (int)sizeof(line)-1) max = (int)sizeof(line)-1;
      ssize_t n = read(fd, line, max);
      if(n<0){ jerr(id,"read"); continue; }
      line[n]=0; // treat as text (HTTP is ASCII)
      // Escape newlines minimally for JSON
      // (good enough for simple requests)
      for(char* p=line; *p; ++p){ if(*p=='\\'){ *p='/'; } } // avoid breaking JSON
      char *buf=line;
      // Build JSON (note: minimal escaping)
      printf("{\"id\":%ld,\"ok\":true,\"data\":\"", id);
      // basic escaping
      for(char* p=buf; *p; ++p){
        if(*p=='\"') { fputs("\\\"", stdout); }
        else if(*p=='\n') { fputs("\\n", stdout); }
        else if(*p=='\r') { fputs("\\r", stdout); }
        else { fputc(*p, stdout); }
      }
      println("\"}");

    } else if(!strcmp(op,"write")){
      int fd = (int)jgetnum(line,"fd",-1);
      if(fd<0){ jerr(id,"bad fd"); continue; }
      char data[120000];
      if(!jget(line,"data",data,sizeof(data))){ data[0]=0; }
      size_t len = strlen(data);
      // unescape minimal sequences used above
      // convert \" -> " ; \n -> newline ; \r -> CR
      char out[120000]; size_t oi=0;
      for(size_t i=0;i<len;i++){
        if(data[i]=='\\' && i+1<len){
          if(data[i+1]=='n'){ out[oi++]='\n'; i++; continue; }
          if(data[i+1]=='r'){ out[oi++]='\r'; i++; continue; }
          if(data[i+1]=='"'){ out[oi++]='"'; i++; continue; }
        }
        out[oi++]=data[i];
      }
      ssize_t w = write(fd,out,oi);
      if(w<0){ jerr(id,"write"); continue; }
      char resp[128];
      snprintf(resp,sizeof(resp),"{\"id\":%ld,\"ok\":true,\"written\":%ld}",id,(long)w);
      println(resp);

    } else if(!strcmp(op,"close")){
      int fd = (int)jgetnum(line,"fd",-1);
      if(fd<0){ jerr(id,"bad fd"); continue; }
      int rc = close(fd);
      if(rc<0){ jerr(id,"close"); continue; }
      char resp[128];
      snprintf(resp,sizeof(resp),"{\"id\":%ld,\"ok\":true}",id);
      println(resp);

    } else if(!strcmp(op,"ping")){
      char resp[64];
      snprintf(resp,sizeof(resp),"{\"id\":%ld,\"ok\":true}",id);
      println(resp);

    } else {
      jerr(id,"unknown op");
    }
  }
  return 0;
}
