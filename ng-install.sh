#!/bin/bash
#Скрипт разворачивания nginx 1.18 c поддержкой ГОСТ TLS. На примере Debian 10.

#1. Установка КриптоПро CSP.
	tar -xvf ./linux-amd64_deb.tgz && cd ./linux-amd64_deb/
	sudo ./install.sh
	sudo dpkg -i lsb-cprocsp-devel_*
	cd ..

#2. Установка дополнительных пакетов, получение исходных текстов
	sudo apt-get update
    sudo apt-get install build-essential patch -y

	wget https://ftp.pcre.org/pub/pcre/pcre-8.45.tar.gz
	tar -xvf ./pcre-8.45.tar.gz

	wget https://zlib.net/zlib-1.2.12.tar.gz
	tar -xvf ./zlib-1.2.12.tar.gz

	wget https://www.openssl.org/source/openssl-1.1.1o.tar.gz
	tar -xvf ./openssl-1.1.1o.tar.gz

#3. Наложение патча nginx.
	wget https://nginx.org/download/nginx-1.18.0.tar.gz
	tar -xvf ./nginx-1.18.0.tar.gz
	cp ./ng-nginx.1.18*.patch ./nginx-1.18.0 && cd ./nginx-1.18.0/
	patch -p1 < ./ng-nginx.1.18*.patch

#4.	Создание системного пользователя.
	sudo adduser --system --no-create-home --group nginx
	
#5. Генерация конфига
	echo "worker_processes 1; 
error_log /var/log/nginx/error.log; 
pid /var/run/nginx.pid; 
worker_rlimit_nofile 8192; 
events { 
    worker_connections 4096; 
} 
http { 
    include conf/mime.types; 
    index index.html index.htm index.php; 
    default_type text/html; 
    log_format main '\$remote_addr - \$remote_user [\$time_local] \$status ' 
        '"\$request" \$body_bytes_sent "\$http_referer" ' 
        '"\$http_user_agent" "\$http_x_forwarded_for"'; 
    access_log /var/log/nginx/access.log main; 
    server { 
        listen 443; 
        server_name $cname; 
        location / { 
            root /var/www; 
            index index.html; 
        } 
        sspi on; 
        sspi_certificate $certserial;
    } 
}" > ./nginx.conf.sample

#6. Сборка.
#cd ./nginx-1.18.0
./configure --user=nginx --group=nginx --with-cc-opt='-fstack-protector -fstack-protector-strong --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Werror=implicit-function-declaration -Winit-self -Wp,-D_FORTIFY_SOURCE=2 -fPIC' --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L/opt/cprocsp/lib/amd64 -lrdrsup -lssp -lcapi10 -lcapi20' --prefix=/opt/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --lock-path=/var/run/lock/nginx.lock --pid-path=/var/run/nginx.pid --with-pcre=../pcre-8.45/ --with-pcre-jit --with-zlib=../zlib-1.2.12/ --with-http_ssl_module --with-http_sspi_module --with-http_stub_status_module --with-openssl=../openssl-1.1.1o/ --with-openssl-opt='no-gost no-comp no-dtls no-deprecated no-dynamic-engine no-engine no-hw-padlock no-nextprotoneg no-psk no-tests no-ts no-ui-console no-ocsp' --with-stream --with-stream_ssl_module --with-stream_sspi_module --with-http_v2_module
make
#	Копирование базовый конфиг в директорию с кодом
sudo cp ./nginx.conf.sample ./nginx-1.18.0/conf/nginx.conf
sudo make install
sudo chown -R nginx:nginx /var/log/nginx/
