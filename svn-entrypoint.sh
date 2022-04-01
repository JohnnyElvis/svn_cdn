#!/bin/bash

function tearDown {
        echo "Shutdown"
        exit 0 
    }

trap tearDown SIGINT SIGHUP SIGTERM

#Liveness probe
#command: ["cat","/tmp/healthy"]
/bin/sh -c "touch /tmp/healthy"

###########################################################
#IMPORTER
###########################################################
if [ ${SVN_WORKLOAD_IS_IMPORTER} = true ]; then
    if [ ! -d ${SVN_DIRECTORY}/${SVN_REPOSITORY} ]; then
        if [ ! -d ${SVN_DIRECTORY} ]; then
                echo "Creating SVN repository started"
                sleep 5 #Waiting for mount
                #Create SVN root directory
                echo mkdir -p ${SVN_DIRECTORY}
                mkdir -p ${SVN_DIRECTORY}
        fi
        
        sleep 1
        #Create SVN repository
        echo svnadmin create --fs-type fsfs ${SVN_DIRECTORY}/${SVN_REPOSITORY}
        svnadmin create --fs-type fsfs ${SVN_DIRECTORY}/${SVN_REPOSITORY}
        #Set SVN UUID (same as in master repo)
        svnadmin setuuid ${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_UUID}

#Create pre-revprop-change
echo "Creating pre-revprop-change"
cat > ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change << EOL
#!/bin/sh
USER="\$3"
if [ "\$USER" = "${SVN_SYNC_USER}" ]; then exit 0; fi
echo "Only the ${SVN_SYNC_USER} user can change revprops" >&2
#exit 1
EOL

        echo chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change
        chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/pre-revprop-change
        echo chown svnadm:svnadm ${SVN_DIRECTORY} -R
        chown svnadm:svnadm ${SVN_DIRECTORY} -R        
        
        


        sleep 1

#Create post-commit-hook
echo "Creating post-commit-hook"
cat > ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/post-commit << EOL
#!/bin/sh
        if [ ! -d ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY} ]; then
                echo "Creating SVN-NFS repository started"
                #Create SVN root directory
                echo mkdir -p ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY}/db
                mkdir -p ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY}/db
                #Copy Version file
                rsync -cavu ${SVN_DIRECTORY}/${SVN_REPOSITORY}/format ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY}/format >> /var/www/rsync.log
                #Fix permissions
                echo chown svnadm:svnadm ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY} -R
                chown svnadm:svnadm ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY} -R
        fi
echo "post-commit-hook"
rsync -cavu --exclude 'current' --exclude 'rep-cache.db' --exclude 'rep-cache.db-journal' --exclude 'write-lock' --exclude 'txn-current' --exclude 'txn-current-lock' --exclude 'transactions' --exclude 'txn-protorevs' ${SVN_DIRECTORY}/${SVN_REPOSITORY}/db/ ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY}/db/
rsync -cavu ${SVN_DIRECTORY}/${SVN_REPOSITORY}/db/current ${SVN_DIRECTORY_NFS}/${SVN_REPOSITORY}/db/current
EOL

        echo chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/post-commit
        chmod +x ${SVN_DIRECTORY}/${SVN_REPOSITORY}/hooks/post-commit


        #SVN Repo init
        su - svnadm -c "svnsync initialize --non-interactive --username ${SVN_SYNC_USER} --password "\"${SVN_SYNC_PW}\"" --trust-server-cert file://${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_SYNC_MASTER}"
        echo "Creating SVN repository finished"
        #Start SVN Sync - Only one instance at a time
        su - svnadm -c "svnsync sync --non-interactive --username ${SVN_SYNC_USER} --password "\"${SVN_SYNC_PW}\"" --trust-server-cert file://${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_SYNC_MASTER}" 
        echo "Initial SVN sync finished"
    fi

echo "SVN Sync started"

while true
    do
    echo "Removing revprop"
    #Remove revprop (if importer was killed)
    su - svnadm -c "svn propdel --revprop -r0 svn:sync-lock file://${SVN_DIRECTORY}/${SVN_REPOSITORY}"
    #Start SVN Sync - Only one instance at a time
    su - svnadm -c "svnsync sync --non-interactive --username ${SVN_SYNC_USER} --password "\"${SVN_SYNC_PW}\"" --trust-server-cert file://${SVN_DIRECTORY}/${SVN_REPOSITORY} ${SVN_SYNC_MASTER}" 
    #Exit code not applied since sync will autorestart in this loop
done

else
    if [ ! -d ${SVN_DIRECTORY} ]; then
        echo "SVN directory missing - exiting"
        exit 0
    fi

###########################################################
#Distributor
###########################################################
#Create authz
echo "Creating authz"
cat > /etc/apache2/dav_svn.authz << EOL
[groups]
roGroup = ${SVN_CLIENT_USER}

[${SVN_REPOSITORY}:/]
@roGroup = r
EOL

#Create DAV module
echo "Creating DAV Module"
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
echo "Creating DAV Config"
cat > /etc/apache2/conf-available/dav_svn.conf << EOL
<IfModule dav_svn_module>
   # Enable a 3Gb*0,8 Subversion data cache for both fulltext and deltas.
  SVNInMemoryCacheSize ${SVNInMemoryCacheSize}
  SVNCacheTextDeltas On
  SVNCacheFullTexts On
  SVNCacheRevProps on
  SVNCompressionLevel ${SVNCompressionLevel}
  SVNAllowBulkUpdates On
</IfModule>
EOL

##Configure mod_status (pretty useless, can be removed)
echo "Configuring mod_status"
cat > /etc/apache2/mods-available/status.conf << EOL
<IfModule mod_status.c>
    ExtendedStatus Off
    <Location /server-status>
        SetHandler server-status
        Order deny,allow
        Deny from all
        Allow from 127.0.0.1
    </Location>
</IfModule>
## vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOL

#Create robots.txt
echo "Creating /var/www/html"
mkdir -p /var/www/html
echo "Creating /var/www/html/robots.txt"
cat > /var/www/html/robots.txt << EOL
User-agent: *
Disallow: /
EOL

	    #Assign hostname to apache
        echo "Assigning ServerName "${SVN_FQDN} 
        echo ServerName ${SVN_FQDN} >> /etc/apache2/apache2.conf

        #Create user
        echo "Creating user " ${SVN_CLIENT_USER}
        htpasswd -cmdb /etc/apache2/svnrepos.users ${SVN_CLIENT_USER} ${SVN_CLIENT_PW}

        #Remove default index.html
        #rm /var/www/html/index.html


        #svnserve -d -r ${SVN_DIRECTORY} --memory-cache-size ${SVNInMemoryCacheSize} --cache-txdeltas yes --cache-fulltexts yes
        service apache2 start
        tail -f /var/log/apache2/error.log
        echo "Something happened"
        exit 0

fi
