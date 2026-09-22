-- Run once by the install hook on a freshly initialised data directory.
-- root@localhost authenticates through the Unix socket peer credentials, so
-- `sudo villagesql.mysql -uroot` needs no password and root can never log in
-- over TCP. Same convention as Ubuntu's mysql-server package.
INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
