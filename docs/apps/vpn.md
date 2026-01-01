# VPN

## Setup Client

https://docs.opnsense.org/manual/how-tos/sslvpn_client.html#create-a-server-certificate



## Troubleshoot

### Renew OpenVPN Certificate

System >> Trust >> Certificates

* Create Certificate
* Create internal certificate
* Descriptive name: SSL VPN Server Certificate <year>
* CA: SSL VPN CA (newest)
* Type: Server Certificate
* Length: 4096
* Digest: SHA512
* Common Name: SSL VPN Server Certificate <year>


### Renew Client Certificate

System >> Trust >> Certificates

* Create Certificate
* Create internal certificate

System >> Access >> Users

* Edit user
* Select new Certificate

VPN >> OpenVPN >> Client Export

* Download certifcate for user
* Use new config in OpenVPN Client

