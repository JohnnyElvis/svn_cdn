FROM    debian:latest

#Update & Install required applications
RUN apt-get update &&\
    apt-get upgrade -y &&\
    apt-get install apache2 apache2-utils subversion libsvn-dev libapache2-mod-svn -y &&\
    apt-get clean
    
#Enable Apache features
RUN a2enmod dav &&\
    a2enmod dav_svn &&\
    a2enmod deflate

#Create service user (not implmented yet)
RUN useradd --home-dir /home/svnadm --comment "SVN Admin User for customer" --create-home svnadm &&\
    usermod -g svnadm -G svnadm www-data

#Create directories
RUN mkdir -p /etc/svn &&\
    mkdir -p /var/log/svnsync

#Variables - ToDo replace with dummies
ENV SVN_SYNC_USER=user1 \
    SVN_SYNC_PW=secret1 \
    SVN_SYNC_MASTER=https://host.domain.lan/svn/live/ \
    SVN_DIRECTORY=/var/www/svn \
    #true for testing
    SVN_WORKLOAD_IS_IMPORTER=false \
    SVN_CLIENT_USER=user2 \
    SVN_CLIENT_PW=secret2

#Fix Module errors
COPY ./fixes/dav.load /etc/apache2/mods-available/dav.load

#Remove default website
RUN rm -rf /var/www/html
RUN unlink /etc/apache2/sites-available/000-default.conf

#Enable Compression
COPY ./svn_config/deflate.conf /etc/apache2/mods-available/deflate.conf
COPY ./svn_config/dav_svn /etc/apache2/mods-available/dav_svn.conf
COPY ./svn_config/* /home/svnadm/

#Set file system permissions
RUN  chown svnadm:svnadm /etc/apache2/mods-available/dav_svn.conf
RUN  chown svnadm:svnadm /var/log/svnsync

#Add entrypoint
ADD svn-entrypoint.sh /home/svnadm/svn-entrypoint.sh
RUN chmod +x /home/svnadm/svn-entrypoint.sh
WORKDIR /home/svnadm
ENTRYPOINT ["./svn-entrypoint.sh"]

#VOLUME ["/var/www/svn"]
EXPOSE 80/tcp
