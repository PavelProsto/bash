cname=$(cat /etc/hostname)
#5. Создание ключа и установка сертификатов
	#Генерация сертификата на тестовом УЦ КриптоПро
	/opt/cprocsp/bin/amd64/cryptcp -creatcert -provtype 80 -rdn "CN=$cname" -cont "\\.\HDIMAGE\\$cname" -certusage 1.3.6.1.5.5.7.3.1 -ku -du -both -exprt -ca http://testgost2012.cryptopro.ru/certsrv/ > /tmp/gen.txt
	sudo -u nginx /opt/cprocsp/bin/amd64/csptest -keys -enum_c -verifyc -fqcn
    sudo cp -R /var/opt/cprocsp/keys/$(whoami)/$cname.000 /var/opt/cprocsp/keys/nginx/$cname.000
    sudo chown -R nginx:nginx /var/opt/cprocsp/keys/nginx/$cname.000
    
    #Экспортируем в файл корневой сертификат тестового УЦ КриптоПро из ключевого контейнера: https://testgost2012.cryptopro.ru/certsrv/certnew.cer?ReqID=CACert&Renewal=1&Enc=bin
		
        
        sudo -u nginx /opt/cprocsp/bin/amd64/csptest -keys -cont "\\.\HDIMAGE\$cname" -saveext /tmp/root.p7b > /tmp/rot.txt
	#Установка корневого сертификата
		sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -inst -store uRoot -file /tmp/root.p7b > /tmp/inroot.txt
	#Устанавливаем сертификат в личные с привязкой
		sudo -u nginx /opt/cprocsp/bin/amd64/csptest -absorb -certs -autoprov > /tmp/ins.txt
	#Получаем серийный номер сертификата
		certserial=$(sudo -u nginx /opt/cprocsp/bin/amd64/certmgr -list -store uMy -dn "CN=$cname" |  egrep '0x.{10,}' | awk '{print $4}')