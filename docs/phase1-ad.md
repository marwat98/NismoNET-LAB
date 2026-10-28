## Phase 1: Domain Controller Installation and Promotion

**Goal.** Build the single server the whole environment depends on: a domain
controller for a new forest, able to resolve its own domain names and
authenticate the accounts created in later phases.

**Starting point.** An empty virtual machine. No domain, no directory, no name
resolution — every later phase assumes this server already exists, so nothing
else could be configured first.

**Steps**
- Installed Windows Server 2022 and renamed the machine to DC01, because the
  name becomes part of the directory and cannot be changed afterwards without
  consequences.
- Assigned the static address 192.168.50.10, since a domain controller must
  stay reachable at a known address rather than depend on DHCP.
- Pointed the server's own DNS client to itself, so that after promotion it
  resolves domain records through its own directory-integrated zone.
- Installed the AD DS role and promoted the server to the first domain
  controller in a new forest, nismonet.local, with the NetBIOS name NISMONET.

```powershell
Rename-Computer -NewName "DC01" -Restart

New-NetIPAddress -InterfaceAlias "Ethernet" `
    -IPAddress 192.168.50.10 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.50.1

Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest -DomainName "nismonet.local" `
    -DomainNetbiosName "NISMONET" `
    -InstallDns
```

**Verification**

![Static addressing and DNS client settings](images/phase1-network-config.png)

Both adapters are listed. The lab adapter holds 192.168.50.10 with a manual
origin and points to itself for DNS — the setting the whole domain depends on.

![Domain and forest](images/phase1-domain-promoted.png)

The forest nismonet.local exists, DC01 holds the PDC emulator role, and the
NetBIOS name NISMONET was generated from the domain name during promotion.

![dcdiag tests passed](images/phase1-dcdiag-passed.png)

The connectivity and services tests pass — the same test that failed during
the DNS problem described below.

**What went wrong.**

The first attempt to configure the adapter failed because I set 127.0.0.1 as
the default gateway. A gateway must be an address that exists on the same
subnet and can actually forward traffic — the loopback address belongs to the
machine itself and routes nothing. The correct split is 192.168.50.1 as the
gateway and 127.0.0.1 as the DNS server.

The second problem appeared later, during verification. `dcdiag` reported
*DC01 failed test Connectivity* and the server could not resolve its own
`_msdcs` record. The cause was the second adapter: it provides internet access
through VirtualBox NAT, and because it carries a default gateway it had the
higher priority, so the controller was asking external DNS servers about its
own domain. Pointing that adapter to the domain DNS server and stopping it
from registering its address resolved it.
See ![Domain controller with two adapters polluting DNS](images/phase1-troubleshooting-dcdiag-passed.png).

**Takeaway.** A domain controller resolves its own domain through itself. That
one setting decides whether anything else in the environment will work, and
it has to be right before the promotion, not after.
