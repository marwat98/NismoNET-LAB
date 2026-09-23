# 🏢  NismoNET IT Support Lab - Corporate Environment Simulation

# 📌 About the Project

The project is a fully functional, virtual IT environment for a small business (NismoNET), created to demonstrate and develop skills in Windows Server administration, PowerShell automation, and technical support (Helpdesk).

The environment simulates the work of 35 employees divided into 6 operational departments. The project includes centralized identity management, group policies, a file server with appropriate restrictions, a ticketing system, and a set of SOPs.

# 🏗️ Architecture and Networking

```mermaid
flowchart TB
    NET([Internet])
    GW[NAT<br/>192.168.50.1]
    NET --- GW

    subgraph LAN [LAN Network 192.168.50.0/24]
        subgraph SRV [Serwery]
            DC01[DC01<br/>192.168.50.10<br/>AD DS · DNS · DHCP]
            TICKET[SRV-TICKET<br/>192.168.50.20<br/>GLPI]
        end
        subgraph WS [Workstation · 35]
            ZARZ[Management<br/>WS-ZARZ-01…03]
            KSIE[Accounting<br/>WS-KSIE-01…03]
            SPRZ[Sale<br/>WS-SPRZ-01…14]
            HELP[Helpdesk<br/>WS-HELP-01…05]
            NETA[Network-Administrator<br/>WS-NETA-01…05]
            CYBR[Cyber-Security<br/>WS-CYBR-01…05]
        end
    end

    GW --- LAN
    DC01 -. DHCP + DNS .-> WS
    TICKET -. LDAP .-> DC01
```
## 📅 Implementation Roadmap
Below is a chronological record of the environment's setup. Each step links to a separate document containing screenshots, the scripts used, and a description of the configuration.

* **[Phase 1: Domain Controller Installation and Configuration](./docs/phase1-ad.md)**
  * Installation and configuration of Windows Server 2022 (DC01).
  * Deployment of AD DS, DNS, and DHCP roles.
  * Creation of a logical OU (Organizational Units) structure that reflects the company’s departments.
 
