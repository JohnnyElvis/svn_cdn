#!/bin/bash

function tearDown {
        echo "Shutdown"
        exit 0 
    }

trap tearDown SIGINT SIGHUP SIGTERM

if [ ${SVN_WORKLOAD_IS_IMPORTER} = true ]; then
    if [ ! -d ${SVN_DIRECTORY} ]; then
        echo "Creating SVN repository started"
        sleep 1 #Waiting for mount
        #Create SVN root directory
        mkdir -p ${SVN_DIRECTORY}

        sleep 1
        #Create SVN repository
        svnadmin create --fs-type fsfs ${SVN_DIRECTORY}/live

        #Copy pre-revprop
        cp pre-revprop-change ${SVN_DIRECTORY}/live/hooks/pre-revprop-change


        #chown svnadm:svnadm /var/www/svn/live/hooks/pre-revprop-change
        chmod +x ${SVN_DIRECTORY}/live/hooks/pre-revprop-change
        chown svnadm:svnadm ${SVN_DIRECTORY} -R

        sleep 1

        #SVN Repo init
        su - svnadm -c "svnsync initialize --non-interactive --username ${SVN_SYNC_USER} --password ${SVN_SYNC_PW} --trust-server-cert file://${SVN_DIRECTORY}/live ${SVN_SYNC_MASTER}"
        echo "Creating SVN repository finished"
    fi

echo "SVN Sync started"

while true
    do
    #Remove revprop (if importer was killed)
    su - svnadm -c "svn propdel --revprop -r0 svn:sync-lock file://${SVN_DIRECTORY}/live"
    #Start SVN Sync - Only one instance at a time
    su - svnadm -c "svnsync sync --non-interactive --username ${SVN_SYNC_USER} --password ${SVN_SYNC_PW} --trust-server-cert file://${SVN_DIRECTORY}/live ${SVN_SYNC_MASTER} #>> /var/log/svnsync/live.log"
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


        #Create user
        htpasswd -cmdb /etc/apache2/svnrepos.users ${SVN_CLIENT_USER} ${SVN_CLIENT_PW}

        service apache2 start
        tail -f /var/log/apache2/error.log
        echo "Something happened"
        exit 0
    fi
fi