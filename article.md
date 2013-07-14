Jouer avec Rok4 et FastCGI
==========================

Ci-dessous la retranscription de quelques notes afin de partager un travail d'investigation initialement réalisé par un de mes ingénieurs systèmes préférés (coucou Laurent ! ;)).

Présentation rapide de Rok4
---------------------------

Rok4 est serveur open-source écrit en C++ qui implémente les standars WMS 1.3.0 et WMTS 1.0.0 de l'OGC (Open Geospatial Consortium). Il permet la diffusion d'images géoréférencées.

Selon sa documentation technique :

> « Il est, par défaut, pensé pour être un serveur statique FastCGI interfacable avec un serveur HTTP traditionnel. »

Pour plus de détails : [rok4.org](http://www.rok4.org/).

Objectif
--------

L'objectif est de s'abstraire de la couche de communication entre un serveur web (ici nginx) et une application FastCGI (ici rok4). Concrètement, dans notre cas, on souhaite pouvoir parler à rok4 en ligne de commande sans passer par HTTP.

**Exemple de requête habituellement envoyée à rok4 (sur HTTP) :**

	# curl "http://localhost:8080/wmts?request=GetVersion&service=WMTS"

			      HTTP          FastCGI
	browser/curl ------> nginx ---------> rok4

_Attention : la requête `GetVersion` ne fait pas partie des standards WMS/WMTS impléméntés par rok4, mais permet d'obtenir la version de l'application déployée par le biais d'un code d'erreur qui, lui, est standard._

**Utilisation souhaitée de rok4 (en ligne de commande directement sur TCP) :**

	# <une commande à définir>

			   FastCGI
	linux box ---------> rok4

_Note : Bien qu'on n'ait pas encore une idée certaine de la commande à exécuter, on se doute bien que `netcat` sera utile :)_

Plan de travail
---------------

Si ça intéresse quelqu'un de jouer avec rok4 de la même manière que celle décrite ici, le projet [rok4-workspace](https://github.com/cuberri/rok4-workspace) permet d'obtenir rapidement une debian 7 avec un rok4 et un nginx installés et configurés. Ce projet tire partie de la recette Chef [rok4](https://github.com/cuberri/rok4) écrite pour l'occasion, qui permet d'installer rok4 à partir des sources téléchargées, et de configurer un jeu de données exemple.

Le projet [rok4-workspace](https://github.com/cuberri/rok4-workspace) contient également les exemples de cet article.

C'est parti !
-------------

_Note : on suppose que rok4 est correctement installé et configuré, et qu'il est servi à travers un nginx, lui aussi bien configuré :). Pour un exemple d'installation et de configuration de cette stack applicative, le lecteur est invité à lire la documentation officielle de rok4 [ici](http://www.rok4.org/documentation), ou bien à utiliser mon propre espace de travail sur lequel est basé cet article, [ici](https://github.com/cuberri/rok4-workspace)_

### 1. Capture et analyse du traffic

Avant de fabriquer une requête à envoyer à rok4 en FastCGI, il nous faut capturer le traffic réseau lors de l'émission d'une requête HTTP. Un coup de `tcpdump` et le tour est joué. La commande suivante lance l'écoute du traffic et écrit le résultat dans un fichier `getversion.pcap` disponible [ici](https://github.com/cuberri/rok4-workspace/blob/master/getversion.pcap?raw=true).

	root@rok4:/vagrant_rok4-workspace# tcpdump -w getversion.pcap -s0 -i any port 9000 &

Exécution de la requête HTTP qui va déclencher la communication FastCGI entre nginx et rok4 :

	root@rok4:/vagrant_rok4-workspace# curl "http://localhost:8080/wmts?request=GetVersion&service=WMTS"

Comme indiqué précédemment, la requête GetVersion est non standard, mais permet d'obtenir la version déployée de rok4 sous forme d'un rapport d'erreur, dont voici la forme :

<script src="https://gist.github.com/cuberri/5995196.js"></script>

Pour « voir » concrètement le traffic capturé, on utilise encore une fois tcpdump :

	root@rok4:/vagrant_rok4-workspace# tcpdump -r getversion.pcap -X -n

La sortie complète est disponible [ici](https://gist.github.com/cuberri/5995198). On peut y voir une session TCP d'une dixaine de paquets pour l'échange FastCGI. On s'intéresse uniquement au paquet contenant le corps de la requête. On l'obtient en tâtonnant à coup de `grep`, et on le met de côté dans un fichier dédié sur lequel on va travailler :

	# tcpdump -r getversion.pcap -X -n | grep -B6 -A34 "ERY_STRINGreques" | tee getversion.req

Voici donc le paquet fautif :

	20:58:05.110369 IP 127.0.0.1.40076 > 127.0.0.1.9000: Flags [P.], seq 1:577, ack 1, win 8198, options [nop,nop,TS val 3575215 ecr 3575215], length 576
        0x0000:  4500 0274 0993 4000 4006 30ef 7f00 0001  E..t..@.@.0.....
        0x0010:  7f00 0001 9c8c 2328 3f56 843f 948e 9276  ......#(?V.?...v
        0x0020:  8018 2006 0069 0000 0101 080a 0036 8daf  .....i.......6..
        0x0030:  0036 8daf 0101 0001 0008 0000 0001 0000  .6..............
        0x0040:  0000 0000 0104 0001 0216 0200 0c1f 5155  ..............QU
        0x0050:  4552 595f 5354 5249 4e47 7265 7175 6573  ERY_STRINGreques
        0x0060:  743d 4765 7456 6572 7369 6f6e 2673 6572  t=GetVersion&ser
        0x0070:  7669 6365 3d57 4d54 530e 0352 4551 5545  vice=WMTS..REQUE
        0x0080:  5354 5f4d 4554 484f 4447 4554 0c00 434f  ST_METHODGET..CO
        0x0090:  4e54 454e 545f 5459 5045 0e00 434f 4e54  NTENT_TYPE..CONT
        0x00a0:  454e 545f 4c45 4e47 5448 0f19 5343 5249  ENT_LENGTH..SCRI
        0x00b0:  5054 5f46 494c 454e 414d 452f 7573 722f  PT_FILENAME/usr/
        0x00c0:  7368 6172 652f 6e67 696e 782f 7777 772f  share/nginx/www/
        0x00d0:  776d 7473 0b05 5343 5249 5054 5f4e 414d  wmts..SCRIPT_NAM
        0x00e0:  452f 776d 7473 0b25 5245 5155 4553 545f  E/wmts.%REQUEST_
        0x00f0:  5552 492f 776d 7473 3f72 6571 7565 7374  URI/wmts?request
        0x0100:  3d47 6574 5665 7273 696f 6e26 7365 7276  =GetVersion&serv
        0x0110:  6963 653d 574d 5453 0c05 444f 4355 4d45  ice=WMTS..DOCUME
        0x0120:  4e54 5f55 5249 2f77 6d74 730d 1444 4f43  NT_URI/wmts..DOC
        0x0130:  554d 454e 545f 524f 4f54 2f75 7372 2f73  UMENT_ROOT/usr/s
        0x0140:  6861 7265 2f6e 6769 6e78 2f77 7777 0f08  hare/nginx/www..
        0x0150:  5345 5256 4552 5f50 524f 544f 434f 4c48  SERVER_PROTOCOLH
        0x0160:  5454 502f 312e 3111 0747 4154 4557 4159  TTP/1.1..GATEWAY
        0x0170:  5f49 4e54 4552 4641 4345 4347 492f 312e  _INTERFACECGI/1.
        0x0180:  310f 0b53 4552 5645 525f 534f 4654 5741  1..SERVER_SOFTWA
        0x0190:  5245 6e67 696e 782f 312e 322e 310b 0952  REnginx/1.2.1..R
        0x01a0:  454d 4f54 455f 4144 4452 3132 372e 302e  EMOTE_ADDR127.0.
        0x01b0:  302e 310b 0552 454d 4f54 455f 504f 5254  0.1..REMOTE_PORT
        0x01c0:  3430 3134 340b 0953 4552 5645 525f 4144  40144..SERVER_AD
        0x01d0:  4452 3132 372e 302e 302e 310b 0453 4552  DR127.0.0.1..SER
        0x01e0:  5645 525f 504f 5254 3830 3830 0b09 5345  VER_PORT8080..SE
        0x01f0:  5256 4552 5f4e 414d 456c 6f63 616c 686f  RVER_NAMElocalho
        0x0200:  7374 0500 4854 5450 530f 0352 4544 4952  st..HTTPS..REDIR
        0x0210:  4543 545f 5354 4154 5553 3230 300f 0b48  ECT_STATUS200..H
        0x0220:  5454 505f 5553 4552 5f41 4745 4e54 6375  TTP_USER_AGENTcu
        0x0230:  726c 2f37 2e32 362e 3009 0e48 5454 505f  rl/7.26.0..HTTP_
        0x0240:  484f 5354 6c6f 6361 6c68 6f73 743a 3830  HOSTlocalhost:80
        0x0250:  3830 0b03 4854 5450 5f41 4343 4550 542a  80..HTTP_ACCEPT*
        0x0260:  2f2a 0000 0104 0001 0000 0000 0105 0001  /*..............
        0x0270:  0000 0000                                ....

### 2. Création d'un fichier binaire à envoyer via FastCGI

Pour rappel, on souhaite envoyer à Rok4 la même requête `GetVersion` émise sur HTTP précédemment, mais cette fois-ci directement sur TCP via FastCGI. La suite consiste donc à fabriquer un binaire contenant uniquement la-dite requête, puis à l'envoyer via un netcat.

Le paquet TCP isolé au-dessus (`getversion.req`) nous apprend que le corps de la requête contient exactement 576 octets de données (voir en toute fin de la ligne 1 : `length 576`). Le début du paquet correspondant à l'entête TCP, il nous faut l'écarter et conserver uniquement le corps.

En travaillant sur le paquet au format texte issu de la capture réseau, on arrive à la commande suivante, qui permet de créer un fichier binaire (`getversion.rok4`) contenant la requête à envoyer (attention, ça pique un peu, mais ça donne l'occasion de réviser awk :P) :

	root@rok4:/vagrant_rok4-workspace# echo -e -n $(awk '/^\t0x*/{print substr($0,11,39)}' getversion.req | tr -d ' ','\n' | awk '{print substr($0,length($0)+1-576*2,576*2)}' | awk '{print gensub("(..)","\\\\x\\1","g",$0)}') > getversion.rok4

Explication de la commande pas à pas :

* Tout d'abord, on conserve uniquement la forme hexédécimale de la sortie issue du tcpdump. C'est à dire les caractères 11 à 39 de chaque ligne contenant des données :
	
		root@rok4:/vagrant_rok4-workspace# awk '/^\t0x*/{print substr($0,11,39)}' getversion.req
		4500 0274 0993 4000 4006 30ef 7f00 0001
		7f00 0001 9c8c 2328 3f56 843f 948e 9276
		8018 2006 0069 0000 0101 080a 0036 8daf
		0036 8daf 0101 0001 0008 0000 0001 0000
		0000 0000 0104 0001 0216 0200 0c1f 5155
		4552 595f 5354 5249 4e47 7265 7175 6573
		743d 4765 7456 6572 7369 6f6e 2673 6572
		7669 6365 3d57 4d54 530e 0352 4551 5545
		5354 5f4d 4554 484f 4447 4554 0c00 434f
		4e54 454e 545f 5459 5045 0e00 434f 4e54
		454e 545f 4c45 4e47 5448 0f19 5343 5249
		5054 5f46 494c 454e 414d 452f 7573 722f
		7368 6172 652f 6e67 696e 782f 7777 772f
		776d 7473 0b05 5343 5249 5054 5f4e 414d
		452f 776d 7473 0b25 5245 5155 4553 545f
		5552 492f 776d 7473 3f72 6571 7565 7374
		3d47 6574 5665 7273 696f 6e26 7365 7276
		6963 653d 574d 5453 0c05 444f 4355 4d45
		4e54 5f55 5249 2f77 6d74 730d 1444 4f43
		554d 454e 545f 524f 4f54 2f75 7372 2f73
		6861 7265 2f6e 6769 6e78 2f77 7777 0f08
		5345 5256 4552 5f50 524f 544f 434f 4c48
		5454 502f 312e 3111 0747 4154 4557 4159
		5f49 4e54 4552 4641 4345 4347 492f 312e
		310f 0b53 4552 5645 525f 534f 4654 5741
		5245 6e67 696e 782f 312e 322e 310b 0952
		454d 4f54 455f 4144 4452 3132 372e 302e
		302e 310b 0552 454d 4f54 455f 504f 5254
		3430 3134 340b 0953 4552 5645 525f 4144
		4452 3132 372e 302e 302e 310b 0453 4552
		5645 525f 504f 5254 3830 3830 0b09 5345
		5256 4552 5f4e 414d 456c 6f63 616c 686f
		7374 0500 4854 5450 530f 0352 4544 4952
		4543 545f 5354 4154 5553 3230 300f 0b48
		5454 505f 5553 4552 5f41 4745 4e54 6375
		726c 2f37 2e32 362e 3009 0e48 5454 505f
		484f 5354 6c6f 6361 6c68 6f73 743a 3830
		3830 0b03 4854 5450 5f41 4343 4550 542a
		2f2a 0000 0104 0001 0000 0000 0105 0001
		0000 0000

* Ensuite, on traite la sortie de la commande précédente afin d'obtenir les données sur une seule ligne

		root@rok4:/vagrant_rok4-workspace# awk '/^\t0x*/{print substr($0,11,39)}' getversion.req | tr -d ' ','\n'
		4500027409934000400630ef7f0000017f0000019c8c23283f56843f948e927680182006006900000101080a00368daf00368daf0101000100080000000100000000000001040001021602000c1f51554552595f535452494e47726571756573743d47657456657273696f6e26736572766963653d574d54530e03524551554553545f4d4554484f444745540c00434f4e54454e545f545950450e00434f4e54454e545f4c454e4754480f195343524950545f46494c454e414d452f7573722f73686172652f6e67696e782f7777772f776d74730b055343524950545f4e414d452f776d74730b25524551554553545f5552492f776d74733f726571756573743d47657456657273696f6e26736572766963653d574d54530c05444f43554d454e545f5552492f776d74730d14444f43554d454e545f524f4f542f7573722f73686172652f6e67696e782f7777770f085345525645525f50524f544f434f4c485454502f312e311107474154455741595f494e544552464143454347492f312e310f0b5345525645525f534f4654574152456e67696e782f312e322e310b0952454d4f54455f414444523132372e302e302e310b0552454d4f54455f504f525434303134340b095345525645525f414444523132372e302e302e310b045345525645525f504f5254383038300b095345525645525f4e414d456c6f63616c686f7374050048545450530f0352454449524543545f5354415455533230300f0b485454505f555345525f4147454e546375726c2f372e32362e30090e485454505f484f53546c6f63616c686f73743a383038300b03485454505f4143434550542a2f2a000001040001000000000105000100000000

* Puis, on conserve uniquement les **576 derniers octets**, c'est à dire uniquement le corps du paquet (rappel basique mais utile :P : un octet = 2 caractères hexa, d'où le « 576*2 ») : 

		root@rok4:/vagrant_rok4-workspace# awk '/^\t0x*/{print substr($0,11,39)}' getversion.req | tr -d ' ','\n' | awk '{print substr($0,length($0)+1-576*2,576*2)}'
		45525f50524f544f434f4c485454502f312e311107474154455741595f494e544552464143454347492f312e310f0b5345525645525f534f4654574152456e67696e782f312e322e310b0952454d4f54455f414444523132372e302e302e310b0552454d4f54455f504f525434303134340b095345525645525f414444523132372e302e302e310b045345525645525f504f5254383038300b095345525645525f4e414d456c6f63616c686f7374050048545450530f0352454449524543545f5354415455533230300f0b485454505f555345525f4147454e546375726c2f372e32362e30090e485454505f484f53546c6f63616c686f73743a383038300b03485454505f4143434550542a2f2a000001040001000000000105000100000000

* Le but du jeu étant de créer un fichier binaire, on transforme la sortie standard afin d'obtenir un jeu de caractères hexédécimal qui sera par la suite redirigé vers un fichier :

		root@rok4:/vagrant_rok4-workspace# awk '/^\t0x*/{print substr($0,11,39)}' getversion.req | tr -d ' ','\n' | awk '{print substr($0,length($0)+1-576,576)}' | awk '{print gensub("(..)","\\\\x\\1","g",$0)}'
		\x45\x52\x5f\x50\x52\x4f\x54\x4f\x43\x4f\x4c\x48\x54\x54\x50\x2f\x31\x2e\x31\x11\x07\x47\x41\x54\x45\x57\x41\x59\x5f\x49\x4e\x54\x45\x52\x46\x41\x43\x45\x43\x47\x49\x2f\x31\x2e\x31\x0f\x0b\x53\x45\x52\x56\x45\x52\x5f\x53\x4f\x46\x54\x57\x41\x52\x45\x6e\x67\x69\x6e\x78\x2f\x31\x2e\x32\x2e\x31\x0b\x09\x52\x45\x4d\x4f\x54\x45\x5f\x41\x44\x44\x52\x31\x32\x37\x2e\x30\x2e\x30\x2e\x31\x0b\x05\x52\x45\x4d\x4f\x54\x45\x5f\x50\x4f\x52\x54\x34\x30\x31\x34\x34\x0b\x09\x53\x45\x52\x56\x45\x52\x5f\x41\x44\x44\x52\x31\x32\x37\x2e\x30\x2e\x30\x2e\x31\x0b\x04\x53\x45\x52\x56\x45\x52\x5f\x50\x4f\x52\x54\x38\x30\x38\x30\x0b\x09\x53\x45\x52\x56\x45\x52\x5f\x4e\x41\x4d\x45\x6c\x6f\x63\x61\x6c\x68\x6f\x73\x74\x05\x00\x48\x54\x54\x50\x53\x0f\x03\x52\x45\x44\x49\x52\x45\x43\x54\x5f\x53\x54\x41\x54\x55\x53\x32\x30\x30\x0f\x0b\x48\x54\x54\x50\x5f\x55\x53\x45\x52\x5f\x41\x47\x45\x4e\x54\x63\x75\x72\x6c\x2f\x37\x2e\x32\x36\x2e\x30\x09\x0e\x48\x54\x54\x50\x5f\x48\x4f\x53\x54\x6c\x6f\x63\x61\x6c\x68\x6f\x73\x74\x3a\x38\x30\x38\x30\x0b\x03\x48\x54\x54\x50\x5f\x41\x43\x43\x45\x50\x54\x2a\x2f\x2a\x00\x00\x01\x04\x00\x01\x00\x00\x00\x00\x01\x05\x00\x01\x00\x00\x00\x00

* Il ne reste plus qu'à écrire le tout dans un fichier en s'assurant d'interpréter les caractères échappés (`\x`), et on arrive à notre commande finale (pfiou !) :

		root@rok4:/vagrant_rok4-workspace# echo -e -n $(awk '/^\t0x*/{print substr($0,11,39)}' getversion.req | tr -d ' ','\n' | awk '{print substr($0,length($0)+1-576,576)}' | awk '{print gensub("(..)","\\\\x\\1","g",$0)}') > getversion.rok4

Le fichier `getversion.rok4` (dispo [ici](https://github.com/cuberri/rok4-workspace/raw/master/getversion.rok4) contient désormais une requête `GetVersion` en binaire. On peut s'amuser à visualiser les chaînes de caractères contenues dans ce fichier pour être certain des paramètres qui vont être passés à Rok4 :

	root@rok4:/vagrant_rok4-workspace# strings getversion.rok4
	QUERY_STRINGrequest=GetVersion&service=WMTS
	REQUEST_METHODGET
	CONTENT_TYPE
	CONTENT_LENGTH
	SCRIPT_FILENAME/usr/share/nginx/www/wmts
	SCRIPT_NAME/wmts
	%REQUEST_URI/wmts?request=GetVersion&service=WMTS
	DOCUMENT_URI/wmts
	DOCUMENT_ROOT/usr/share/nginx/www
	SERVER_PROTOCOLHTTP/1.1
	GATEWAY_INTERFACECGI/1.1
	SERVER_SOFTWAREnginx/1.2.1
	        REMOTE_ADDR127.0.0.1
	REMOTE_PORT40144
	        SERVER_ADDR127.0.0.1
	SERVER_PORT8080
	        SERVER_NAMElocalhost
	HTTPS
	REDIRECT_STATUS200
	HTTP_USER_AGENTcurl/7.26.0
	HTTP_HOSTlocalhost:8080
	HTTP_ACCEPT*/*

### 3. Envoi de la requête en FastCGI sur TCP

Maintenant que le fichier `getversion.rok4` est créé, il ne reste plus qu'à envoyer son contenu sur le port d'écoute de rok4, et à écrire la sortie de la commande dans un nouveau fichier :

	root@rok4:/vagrant_rok4-workspace# cat getversion.rok4 | nc 0 9000 | dd of=getversion.fastcgi

Le résultat peut être visualisé de la même manière que précédemment :

	root@rok4:/vagrant_rok4-workspace# strings getversion.fastcgi
	Status: 501 Not implemented
	Content-Type: text/xml
	Content-Disposition: filename="message.xml"
	<ExceptionReport xmlns="http://www.opengis.net/ows/1.1">
	<Exception exceptionCode="OperationNotSupported" >
	  L'operation getversion n'est pas prise en charge par ce serveur.ROK4-0.13.1
	</Exception>
	</ExceptionReport>

Et voilà !

Conclusion
----------

Ces opérations nous ont permis de s'abstraire du serveur web normalement utilisé pour communiquer avec Rok4, de manière à dialoguer de façon directe avec l'application.

Bon, j'avoue volontiers que l'intérêt dans la vraie vie est somme toute assez limité :). Je note tout de même deux utilisations pratiques :

* Tests de performance « pure » de l'application (i.e. : sans nginx/apache en amont) ;
* Tests fonctionnels lors d'une montée de version : on peut par exemple enrichir des scripts de déploiement afin d'exécuter un `GetVersion` et s'assurer du fonctionnement du serveur avant sa remise dans un flux de production.

Pour finir, un clin d'oeil à Laurent (mon ingé sys favori, je le dirai jamais assez :)) pour le travail réalisé bien avant moi sur le sujet.
