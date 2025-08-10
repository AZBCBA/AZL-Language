// bind_test.c
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <string.h>
#include <unistd.h>
int main(){int fd=socket(AF_INET,SOCK_STREAM,0);int on=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&on,sizeof(on));
struct sockaddr_in sa;memset(&sa,0,sizeof(sa));sa.sin_family=AF_INET;sa.sin_port=htons(8080);sa.sin_addr.s_addr=htonl(INADDR_ANY);
bind(fd,(void*)&sa,sizeof(sa));listen(fd,128);sleep(300);return 0;}
