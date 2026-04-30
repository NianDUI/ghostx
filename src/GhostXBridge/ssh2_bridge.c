#include <libssh2.h>
#include <libssh2_sftp.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>

// --- SSH2 Bridge: minimal C wrappers for dlopen-based Swift calling ---

void* ghostx_ssh2_init(void) {
    int rc = libssh2_init(0);
    return rc == 0 ? (void*)1 : NULL;
}

void ghostx_ssh2_exit(void) {
    libssh2_exit();
}

// --- Session ---

void* ghostx_ssh2_session_init(void) {
    return libssh2_session_init();
}

int ghostx_ssh2_session_free(void* session) {
    return libssh2_session_free((LIBSSH2_SESSION*)session, NULL);
}

int ghostx_ssh2_session_startup(void* session, int sock) {
    return libssh2_session_startup((LIBSSH2_SESSION*)session, sock);
}

int ghostx_ssh2_session_handshake(void* session, int sock) {
    return libssh2_session_handshake((LIBSSH2_SESSION*)session, sock);
}

int ghostx_ssh2_session_disconnect(void* session, const char* desc) {
    return libssh2_session_disconnect((LIBSSH2_SESSION*)session, desc);
}

int ghostx_ssh2_session_last_errno(void* session) {
    return libssh2_session_last_errno((LIBSSH2_SESSION*)session);
}

void ghostx_ssh2_session_last_error(void* session, char** errmsg, int* errmsg_len) {
    libssh2_session_last_error((LIBSSH2_SESSION*)session, errmsg, errmsg_len, 0);
}

int ghostx_ssh2_session_set_timeout(void* session, long timeout) {
    libssh2_session_set_timeout((LIBSSH2_SESSION*)session, timeout);
    return 0;
}

int ghostx_ssh2_session_set_blocking(void* session, int blocking) {
    libssh2_session_set_blocking((LIBSSH2_SESSION*)session, blocking);
    return 0;
}

int ghostx_ssh2_session_keepalive_config(void* session, int want_reply, unsigned interval) {
    return libssh2_keepalive_config((LIBSSH2_SESSION*)session, want_reply, interval);
}

int ghostx_ssh2_session_keepalive_send(void* session, int* seconds_to_next) {
    return libssh2_keepalive_send((LIBSSH2_SESSION*)session, seconds_to_next);
}

// --- Auth ---

int ghostx_ssh2_userauth_password(void* session, const char* username, const char* password) {
    return libssh2_userauth_password((LIBSSH2_SESSION*)session, username, password);
}

int ghostx_ssh2_userauth_publickey_fromfile(void* session, const char* username,
    const char* publickey, const char* privatekey, const char* passphrase) {
    return libssh2_userauth_publickey_fromfile((LIBSSH2_SESSION*)session,
        username, publickey, privatekey, passphrase);
}

char* ghostx_ssh2_userauth_list(void* session, const char* username) {
    return libssh2_userauth_list((LIBSSH2_SESSION*)session, username, (unsigned int)strlen(username));
}

// --- Channel ---

void* ghostx_ssh2_channel_open_session(void* session) {
    return libssh2_channel_open_session((LIBSSH2_SESSION*)session);
}

int ghostx_ssh2_channel_close(void* channel) {
    return libssh2_channel_close((LIBSSH2_CHANNEL*)channel);
}

int ghostx_ssh2_channel_free(void* channel) {
    return libssh2_channel_free((LIBSSH2_CHANNEL*)channel);
}

int ghostx_ssh2_channel_request_pty(void* channel, const char* term) {
    return libssh2_channel_request_pty((LIBSSH2_CHANNEL*)channel, term);
}

int ghostx_ssh2_channel_request_pty_size(void* channel, int width, int height) {
    return libssh2_channel_request_pty_size((LIBSSH2_CHANNEL*)channel, width, height);
}

int ghostx_ssh2_channel_shell(void* channel) {
    return libssh2_channel_shell((LIBSSH2_CHANNEL*)channel);
}

int ghostx_ssh2_channel_exec(void* channel, const char* command) {
    return libssh2_channel_exec((LIBSSH2_CHANNEL*)channel, command);
}

ssize_t ghostx_ssh2_channel_read(void* channel, char* buf, size_t buflen) {
    return libssh2_channel_read((LIBSSH2_CHANNEL*)channel, buf, buflen);
}

ssize_t ghostx_ssh2_channel_write(void* channel, const char* buf, size_t buflen) {
    return libssh2_channel_write((LIBSSH2_CHANNEL*)channel, buf, buflen);
}

int ghostx_ssh2_channel_setenv(void* channel, const char* name, const char* value) {
    return libssh2_channel_setenv((LIBSSH2_CHANNEL*)channel, name, value);
}

int ghostx_ssh2_channel_eof(void* channel) {
    return libssh2_channel_eof((LIBSSH2_CHANNEL*)channel);
}

// --- Tunnels ---

void* ghostx_ssh2_channel_direct_tcpip(void* session, const char* host, int port,
                                        const char* shost, int sport) {
    return libssh2_channel_direct_tcpip((LIBSSH2_SESSION*)session, host, port, shost, sport);
}

void* ghostx_ssh2_channel_forward_listen(void* session, int port) {
    return libssh2_channel_forward_listen((LIBSSH2_SESSION*)session, port);
}

void* ghostx_ssh2_channel_forward_accept(void* listener) {
    return libssh2_channel_forward_accept((LIBSSH2_LISTENER*)listener);
}

int ghostx_ssh2_channel_forward_cancel(void* listener) {
    return libssh2_channel_forward_cancel((LIBSSH2_LISTENER*)listener);
}

// --- SFTP ---

void* ghostx_ssh2_sftp_init(void* session) {
    return libssh2_sftp_init((LIBSSH2_SESSION*)session);
}

int ghostx_ssh2_sftp_shutdown(void* sftp) {
    return libssh2_sftp_shutdown((LIBSSH2_SFTP*)sftp);
}

void* ghostx_ssh2_sftp_open(void* sftp, const char* filename, unsigned long flags,
                             long mode, int open_type) {
    return libssh2_sftp_open((LIBSSH2_SFTP*)sftp, filename, flags, mode, open_type);
}

ssize_t ghostx_ssh2_sftp_read(void* handle, char* buf, size_t count) {
    return libssh2_sftp_read((LIBSSH2_SFTP_HANDLE*)handle, buf, count);
}

ssize_t ghostx_ssh2_sftp_write(void* handle, const char* buf, size_t count) {
    return libssh2_sftp_write((LIBSSH2_SFTP_HANDLE*)handle, buf, count);
}

int ghostx_ssh2_sftp_close(void* handle) {
    return libssh2_sftp_close((LIBSSH2_SFTP_HANDLE*)handle);
}

void* ghostx_ssh2_sftp_opendir(void* sftp, const char* path) {
    return libssh2_sftp_open_ex((LIBSSH2_SFTP*)sftp, path, (unsigned int)strlen(path),
        LIBSSH2_SFTP_OPENDIR, 0, LIBSSH2_SFTP_OPEN_TYPE_DIR);
}

int ghostx_ssh2_sftp_readdir(void* handle, char* buf, size_t buf_len, void* attrs) {
    return libssh2_sftp_readdir((LIBSSH2_SFTP_HANDLE*)handle, buf, buf_len, (LIBSSH2_SFTP_ATTRIBUTES*)attrs);
}

int ghostx_ssh2_sftp_closedir(void* handle) {
    return libssh2_sftp_close((LIBSSH2_SFTP_HANDLE*)handle);
}

int ghostx_ssh2_sftp_mkdir(void* sftp, const char* path, long mode) {
    return libssh2_sftp_mkdir((LIBSSH2_SFTP*)sftp, path, (unsigned int)strlen(path), mode);
}

int ghostx_ssh2_sftp_unlink(void* sftp, const char* filename) {
    return libssh2_sftp_unlink((LIBSSH2_SFTP*)sftp, filename, (unsigned int)strlen(filename));
}

int ghostx_ssh2_sftp_rename(void* sftp, const char* src, const char* dst) {
    return libssh2_sftp_rename((LIBSSH2_SFTP*)sftp, src, (unsigned int)strlen(src),
                               dst, (unsigned int)strlen(dst));
}

int ghostx_ssh2_sftp_stat(void* sftp, const char* path, void* attrs) {
    return libssh2_sftp_stat((LIBSSH2_SFTP*)sftp, path, (unsigned int)strlen(path),
                             LIBSSH2_SFTP_STAT, (LIBSSH2_SFTP_ATTRIBUTES*)attrs);
}

// --- Socket helpers ---

int ghostx_socket_connect(const char* host, int port) {
    struct hostent* hp = gethostbyname(host);
    if (!hp) return -1;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((unsigned short)port);
    memcpy(&addr.sin_addr, hp->h_addr, (size_t)hp->h_length);

    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock);
        return -1;
    }
    return sock;
}

void ghostx_socket_close(int sock) {
    if (sock >= 0) close(sock);
}
