#!/bin/bash

function tearDown {
        echo "Shutdown"
        exit 0 
    }

trap tearDown SIGINT SIGHUP SIGTERM

if [ ${SVN_WORKLOAD_IS_IMPORTER} = true ]; then
    if [ ! -d ${SVN_DIRECTORY} ]; then
        echo "Creating SVN repository started"
        sleep 5 #Waiting for mount
        #Create SVN root directory
        echo mkdir -p ${SVN_DIRECTORY}
        mkdir -p ${SVN_DIRECTORY}

        sleep 1
        #Create SVN repository
        echo svnadmin create --fs-type fsfs ${SVN_DIRECTORY}/${SVN_REPOSITORY}
        svnadmin create --fs-type fsfs ${SVN_DIRECTORY}/${SVN_REPOSITORY}

        #Copy pre-revprop
        echo cp pre-revprop-change ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change
        cp pre-revprop-change ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change

        echo chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change
        chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change
        echo chown svnadm:svnadm ${SVN_DIRECTORY} -R
        chown svnadm:svnadm ${SVN_DIRECTORY} -R

        sleep 1

        #SVN Repo init
        su - svnadm -c "svnsync initialize --non-interactive --username ${SVN_SYNC_USER} --password ${SVN_SYNC_PW} --trust-server-cert file://${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_SYNC_MASTER}"
        echo "Creating SVN repository finished"
    fi

echo "SVN Sync started"

while true
    do
    #Remove revprop (if importer was killed)
    su - svnadm -c "svn propdel --revprop -r0 svn:sync-lock file://${SVN_DIRECTORY}/${SVN_REPOSITORY}"
    #Start SVN Sync - Only one instance at a time
    su - svnadm -c "svnsync sync --non-interactive --username ${SVN_SYNC_USER} --password ${SVN_SYNC_PW} --trust-server-cert file://${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_SYNC_MASTER}" 
    #Exit code not applied since sync will autorestart in this loop
done

else
    if [ ${SVN_WORKLOAD_IS_IMPORTER} = false ]; then
        if [ ! -d ${SVN_DIRECTORY} ]; then
            echo "SVN directory missing - exiting"
            exit 0
        fi

        #Copy authz
        #cp dav_svn.authz /etc/apache2/dav_svn.authz

cat > /etc/apache2/dav_svn.authz << EOL
[groups]
roGroup = ${SVN_CLIENT_USER}

[live:/]
@roGroup = r
EOL

#Create DAV module
cat > /etc/apache2/mods-available/dav_svn.conf << EOL
<Location /svn>
   DAV svn
   SVNParentPath ${SVN_DIRECTORY}
   SVNPathAuthz off
   # Limit write permission to list of valid users.
#   <LimitExcept GET PROPFIND OPTIONS REPORT>
      # Require SSL connection for password protection.
      # SSLRequireSSL

      AuthType Basic
      AuthName "Authorization SVN"
      AuthUserFile /etc/apache2/svnrepos.users
      # To enable authorization via mod_authz_svn
      AuthzSVNAccessFile /etc/apache2/dav_svn.authz
      Require valid-user
#   </LimitExcept>
</Location>
EOL

#Create DAV config
cat > /etc/apache2/conf-available/dav_svn.conf << EOL
<IfModule dav_svn_module>
   # Enable a 3Gb*0,8 Subversion data cache for both fulltext and deltas.
  SVNInMemoryCacheSize ${SVNInMemoryCacheSize}
  SVNCacheTextDeltas On
  SVNCacheFullTexts On
  SVNCacheRevProps on
  SVNCompressionLevel ${SVNCompressionLevel}
  SVNAllowBulkUpdates Off
</IfModule>
EOL

#Configure mod_status
Listen 8001
ExtendedStatus On
<VirtualHost *:8001>
    <Location /server-status>
        SetHandler server-status
        Order deny,allow
        Deny from all
        Allow from localhost ip6-localhost 
    #    Allow from .example.com
    </Location>
</VirtualHost>
</IfModule>
EOL

        #Set SVN UUID (same as in master repo)
        svnadmin setuuid ${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_UUID}

        #Assign hostname to apache
        echo ServerName ${SVN_FQDN} >> /etc/apache2/apache2.conf

        #Create user
        htpasswd -cmdb /etc/apache2/svnrepos.users ${SVN_CLIENT_USER} ${SVN_CLIENT_PW}

        #Remove default index.html
        #rm /var/www/html/index.html


        #svnserve -d -r ${SVN_DIRECTORY} --memory-cache-size ${SVNInMemoryCacheSize} --cache-txdeltas yes --cache-fulltexts yes
        service apache2 start
        tail -f /var/log/apache2/error.log
        echo "Something happened"
        exit 0
    fi
fi
