# Network

The Raspberries are in two networks. The internal network and a special DMZ for the external communication
of the K8S Cluster. This is not done by actual multiple network interfaces but with vlan.

Just by chance my firewall had a free network interface so I chose to actually use a seperate network
interface for the DMZ there. I would have used vlan there as well.

I could use pure port-forwarding to the MetalLB-IP of the Cluster.


## Opnsense

On my Opnsense firewall I have to configure several things:

1. WAN interface to accept inbound web (443) traffic
2. Add NAT port-forward for the MetalLB-IP

## VPN

The firewall has OpenVPN installed. The users are configured on the firewall
and the authentication uses OTPT.

The OTP from the Google Authenticator is entered with the password in the
following form: `<password><otp>`.

