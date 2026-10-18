## Phase 2: Network Addressing and DHCP

**Goal.**
Provide workstations with automatic addressing that is sufficient to join and use the domain — not only an IP address, but also the gateway, the domain DNS server and the domain suffix.

**Starting point.** 
DC01 was already a domain controller for nismonet.local with a static address 192.168.50.10 and a working DNS server. No DHCP role was installed, so clients had to be configured manually.

**Steps**
- Installed the DHCP role together with its management tools, which also provide the PowerShell cmdlets.
- Created the scope 192.168.50.100–200, leaving the lower range free for devices that need a fixed address.
- Set options 003, 006 and 015 so that clients receive the gateway, the domain DNS server and the domain suffix along with the address.
- Authorized the server in Active Directory, which a domain DHCP server requires before it serves any lease.

​```powershell
Add-DhcpServerv4Scope -Name "NismoNET-LAN" `
    -StartRange 192.168.50.100 `
    -EndRange 192.168.50.200 `
    -SubnetMask 255.255.255.0 `
    -State Active `
    -LeaseDuration 8.00:00:00
​```

**Verification**
[DHCP lease for WS-SPRZ-01](imges/phase2-dhcp-lease.png)

WS-SPRZ-01 holds an active lease from the configured pool, registered with
the domain suffix applied.

**What went wrong.** 
The server stopped serving addresses without any visible
error. The scope was active and correctly configured, but clients fell back to
APIPA addresses. The DHCP server log showed event code 56 — authorization
failure. Re-registering the server in Active Directory changed the entry to
code 55 and leases resumed immediately. The scope was also missing options 006
and 015, which would have prevented domain logon even once addressing worked.
See (..).

**Takeaway.** Five things were genuinely misconfigured along the way, but none
of them was the cause. Since then I check the server log before testing the
client.
