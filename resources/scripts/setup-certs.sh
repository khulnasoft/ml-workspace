SSLNAME=cert

[ -f /run/secrets/$SSLNAME.crt ] && cp /run/secrets/$SSLNAME.crt ${SSL_RESOURCES_PATH}/$SSLNAME.crt
[ -f /run/secrets/$SSLNAME.key ] && cp /run/secrets/$SSLNAME.key ${SSL_RESOURCES_PATH}/$SSLNAME.key
[ -f /run/secrets/$SSLNAME.pem ] && cp /run/secrets/$SSLNAME.pem ${SSL_RESOURCES_PATH}/$SSLNAME.pem

if [ ! -f ${SSL_RESOURCES_PATH}/$SSLNAME.crt ]; then
    echo "Generating self-signed certificate for SSL/HTTPS."
    SSLDAYS=365

    if ! openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout $SSLNAME.key \
        -out $SSLNAME.crt \
        -days $SSLDAYS \
        -subj '/C=DE/ST=Khulnasoft/L=Khulnasoft/CN=localhost'; then
        echo "Error: Failed to generate SSL certificate"
        exit 1
    fi

    mv $SSLNAME.crt ${SSL_RESOURCES_PATH}/$SSLNAME.crt
    mv $SSLNAME.key ${SSL_RESOURCES_PATH}/$SSLNAME.key
else
    echo "Certificate for SSL/HTTPS was found in "${SSL_RESOURCES_PATH}
fi

# trust certificate. used in case containers share the same certificate
cp ${SSL_RESOURCES_PATH}/$SSLNAME.crt /usr/local/share/ca-certificates/
# update certificates, but dont print out information
update-ca-certificates > /dev/null

# Add following add certificates to certify python package
cat ${SSL_RESOURCES_PATH}/$SSLNAME.crt >> ${CONDA_PYTHON_DIR}/site-packages/certifi/cacert.pem
