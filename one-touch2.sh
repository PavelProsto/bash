#!/bin/bash
#Скрипт разворачивания nginx 1.18 c поддержкой ГОСТ TLS. На примере Debian 10.

#cdir=$(pwd -LP)
cname=$(cat /etc/hostname)
#Проверки дополнить - проверка установленных компонентов провайдера, проверка наличия файлов провайдера для установки, проверка наличия патча
#предусмотреть возможность скачать патч и файлы nginx с внутреннего сервака

#if ! [ls ./ | grep linux-amd64_deb*]


#1. Установка КриптоПро CSP.
	tar -xvf ./linux-amd64_deb.tgz && cd ./linux-amd64_deb/
	sudo ./install.sh
	sudo dpkg -i lsb-cprocsp-devel_*
	cd ..

#2. Установка дополнительных пакетов, получение исходных текстов
	sudo apt-get install build-essential patch -y

	wget https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz
	tar -xvf ./pcre-8.44.tar.gz

	wget https://zlib.net/zlib-1.2.11.tar.gz
	tar -xvf ./zlib-1.2.11.tar.gz

	wget https://www.openssl.org/source/openssl-1.1.1h.tar.gz
	tar -xvf ./openssl-1.1.1h.tar.gz

#3. Наложение патча nginx.
	wget https://nginx.org/download/nginx-1.18.0.tar.gz
	tar -xvf ./nginx-1.18.0.tar.gz
	cp ./ng-nginx.1.18*.patch ./nginx-1.18.0 && cd ./nginx-1.18.0/
	patch -p1 < ./ng-nginx.1.18*.patch

#4.	Создание системного пользователя.
	sudo adduser --system --no-create-home --group nginx

#5. Создание ключа и установка сертификатов
	#Генерация сертификата на тестовом УЦ КриптоПро
		/opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 80 -rdn "CN=$cname" -cont "\\.\HDIMAGE\\$cname" -certusage 1.3.6.1.5.5.7.3.1 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv/ > /tmp/gen.txt
	sudo -u nginx /opt/cprocsp/bin/amd64/csptest -keys -enum_c -verifyc -fqcn
    sudo cp -R /var/opt/cprocsp/keys/$(whoami)/$cname.000 /var/opt/cprocsp/keys/nginx/$cname.000
    sudo chown -R nginx:nginx /var/opt/cprocsp/keys/nginx/$cname.000
    
    #Экспортируем в файл корневой сертификат тестового УЦ КриптоПро из ключевого контейнера: https://testgost2012.cryptopro.ru/certsrv/certnew.cer?ReqID=CACert&Renewal=1&Enc=bin
		
        
        sudo -u nginx /opt/cprocsp/bin/amd64/csptest -keys -cont '\\.\HDIMAGE\srv1' -saveext /tmp/root.p7b > /tmp/rot.txt
	#Установка корневого сертификата
		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -inst -store uRoot -file /tmp/root.p7b > /tmp/inroot.txt
	#Устанавливаем сертификат в личные с привязкой
		sudo -u nginx /opt/cprocsp/bin/amd64/csptest -absorb -certs -autoprov > /tmp/ins.txt
	#Получаем серийный номер сертификата
		certserial=$(sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -list -store uMy -dn "CN=$cname" |  egrep '(Серийный номер)|(Serial number)' | awk '{print $4}')
	
#6. Генерация конфига
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

#7. Сборка.
#cd ./nginx-1.18.0
./configure --user=nginx --group=nginx --with-cc-opt='-fstack-protector -fstack-protector-strong --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Werror=implicit-function-declaration -Winit-self -Wp,-D_FORTIFY_SOURCE=2 -fPIC' --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L/opt/cprocsp/lib/amd64 -lrdrsup -lssp -lcapi10 -lcapi20' --prefix=/opt/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --lock-path=/var/run/lock/nginx.lock --pid-path=/var/run/nginx.pid --with-pcre=../pcre-8.44/ --with-pcre-jit --with-zlib=../zlib-1.2.11/ --with-http_ssl_module --with-http_sspi_module --with-http_stub_status_module --with-openssl=../openssl-1.1.1h/ --with-openssl-opt='no-gost no-comp no-dtls no-deprecated no-dynamic-engine no-engine no-hw-padlock no-nextprotoneg no-psk no-tests no-ts no-ui-console no-ocsp' --with-stream --with-stream_ssl_module --with-stream_sspi_module --with-http_v2_module
make
#	Копирование базовый конфиг в директорию с кодом
sudo cp ./nginx.conf.sample ./nginx-1.18.0/conf/nginx.conf
sudo make install
sudo chown -R nginx:nginx /var/log/nginx/

sudo systemctl enable nginx
sudo systemctl start nginx

:end

#	Перенос init скрипта.
#	sudo cp $mydir/nginx.init /etc/init.d/nginx
#	sudo chmod +x /etc/init.d/nginx
#	sudo systemctl daemon-reload
	
#5. Работа с ключами и сертификатами. Создавайте ключи без паролей.
#	Если у вас уже есть контейнер с ключем, то необходимо поместить его в /var/opt/cprocsp/keys/nginx/, изменить права, сделать владельцем пользователя от которого запускается nginx
#		chmod 700 /var/opt/cprocsp/keys/nginx/key_cont.000
#		chmod 600 /var/opt/cprocsp/keys/nginx/key_cont.000/*
#		chown -R nginx:nginx /var/opt/cprocsp/keys/nginx/key_cont.000/
#	Установка в хранилище всех сертификатов из всех доступных контейнеров
#		sudo -u nginx /opt/cprocsp/bin/amd64/csptest -absorb -certs -autoprov
#	Экспорт RSA ключа и сертификата из PFX
#		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -inst -provtype 24 -pfx -pin 123 -file ~/test.pfx







#		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -inst -store uCa -file /path/to/intermediate.cer
	


#	Получение серийного номера сертификата
#		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -list
#	Для режима двусторонней авутентификации (MutualTLS) необходимо установить корневые сертификаты клиентов в хранилище, указанное в конфиге (sspi_verify_client on; sspi_client_certificate TrustedCerts;)
#		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -inst -store uTrustedCerts -file /path/to/ClientRoot.cer

#6. Добавление серийного номера сертификата в конфигурационный файл nginx.conf
#	Необходимо отредактировать /etc/nginx/nginx.conf, заменить серийный номер в sspi_certificate на свой.
#	sudo systemctl start nginx
#	
#7. Ошибки при запуске логируются в /var/log/nginx/error.log или /var/log/syslog
#	При успешном запуске nginx откройте страницу https://site.ru проверьте в адресной строке, что соединение зашифровано.
#	Так же можно пользоваться тестовой утилитойиз состава CSP
#	"C:\Program Files\Crypto Pro\CSP\csptest.exe" -tlsc -server site.ru -port 443 -proto 6 -ciphers ff85:c100:c101:c102 -nosave -v
#	Более подробно "C:\Program Files\Crypto Pro\CSP\csptest.exe" -tlsc -help