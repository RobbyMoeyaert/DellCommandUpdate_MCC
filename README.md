# DellCommandUpdate_MCC
Integrate Dell Command Update with Microsoft Connected Cache
## Getting Started

This guide will detail how to set up this particular integration between Dell Command Update and a Microsoft Connected Cache

### Prerequisites

1) Microsoft Connected Cache

An SCCM environment that supports Microsoft Connected Cache and has at least one Distribution point configured as a MCC.
Please refer to the official Microsoft documentation on how to do this.

https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/microsoft-connected-cache

Windows should be made aware of this MCC either through direct GPO configuration or by configuring the SCCM client to configure Delivery Optimization settings.

2) Dell Command Update

A Dell Command Update installation. 3.1 or higher required.
Please refer to the official Dell documentation on how to do this.

https://www.dell.com/support/article/en-us/sln311129/dell-command-update?lang=en

### Overview

Dell Command Update (DCU) is Dell's tooling for deploying driver and firmware updates to clients.

In its default configuration it will scan for applicable updates versus a catalog file hosted on Dell's CDN and also download the sources for any updates from that same CDN.

The problem with this is that such a setup is problematic for environments with remote sites behind a WAN link, as total download size can easily surpass 1GB per client when running a full update on a freshly imaged machine.

Dell's own solution for this is to use Dell Repository Manager (DRM) to create an onprem repository of sources and then use a custom Catalog.xml file for DCU to point DCU towards the DRM repository. While this technically works, creating and maintaining the onprem repository is quite labour intensive, and the total size of the repository can easily reach 100 GB, of which maybe half is actually needed.

On top of this, there is the issue with pointing clients towards the repository in a dynamic way, since you would be hosting a copy of this repository in each site behind a WAN link.

My solution for this was to piggyback on a solution Microsoft had already provided for this exact problem, but aimed at Microsoft's own CDN downloads: Delivery Optimization In-Network Cache (DOINC), now rebranded as Microsoft Connected Cache (MCC).

#### Background

To summarize briefly, the SCCM version of MCC uses IIS Application Request Routing to become a HTTP caching proxy for Microsoft's CDNs.

It works by defining the CDNs as Server Farms in IIS on the DP, with associated cache, and then using specific ARR rules to allow clients to connect to the DP and download the content from the CDN through the DP.

Since there is nothing proprietary about this, it is just using existing IIS functionality in a clever way, it is fairly trivial to extend upon.

### Setup

#### Microsoft Connected Cache configuration extension
This section describes how to manually configure IIS and LEDBAT for this extension. All of this should be scriptable.

To start, log into the MCC enabled distribution point with an account that has Administrator privileges on said server.

##### IIS configuration

Open the IIS console and navigate to "Server Farms"

Click "Create Server farm"

Call it "Farm_downloads.dell.com" and add "downloads.dell.com" as server address.

Click "NO" when asked to automatially create URL rewrite rules.

Select the newly created server farm and edit settings

-Under "Caching", change duration to 600 seconds

-Under "Proxy", change timeout to 300 seconds and response buffer treshold to 1024kb

Note: these are the same settings Microsoft configures on their own CDN server farms when setting up MCC

Navigate to "Sites" and select "Default" website

Open "URL Rewrite"

Click "Add Rule", and select "Blank Rule"

Configure the following:

-Name : ARR_downloads.dell.com

-Match URL : .*

-Conditions : {URL} matches pattern /DellDownloads/(.*)

-Server Variables : HTTP_HOST downloads.dell.com, replace existing value

-Action : Rewrite, http://Farm_downloads.dell.com/{C:1} , Stop processing subsequent rules

This concludes the IIS part of the configuration.

The net result is now that the URL

"http://yoursccmdp.fqdn/DellDownloads" is a caching proxy for http://downloads.dell.com".

##### LEDBAT configuration
LEDBAT is a throttling technology available from Windows Server 2016 and up. It can be configured by checking a checkbox in the properties of the SCCM distribution point in the SCCM console.

The rules SCCM configures are aimed at connections coming in on port 80 and 443, which are the ports the DP will serve content on. This is good as it will be re-used in this configuration here, since port 80 is in use.

However this only covers the connection between the DP and the client, there is still the issue that the DP will download the content from the CDN and thus might still saturate the WAN link itself. Therefore we also want to configure LEDBAT between the server and the CDN.

First, verify that LEDBAT is configured on the DP. In a Powershell admin prompt type

```
Get-NetTransportFilter
```

And verify you see the rules for port 80 and 443

Next, we will add a LEDBAT rule for connection to the CDN. However, which rule we need to add depends on the environment

-If you are using a corporate proxy and have configured MCC to use it, you need to use the IP of the proxy since network-wise the TCP connection will be between the server and the proxy

-If you are not using a proxy, you need to use the IP of the CDN. This IP can be retreived by doing a DNS lookup for "downloads.dell.com". In this example I will be using 152.199.20.130

Add the LEDBAT rule by entering the following on the Powershell prompt

```
New-NetTransportFilter -SettingName InternetCustom -Protocol TCP -DestinationPrefix "152.199.20.130/32"
```

Verify again that the rule is added

This concludes the LEDBAT part of the configuration

#### Dell Command Update configuration script

This section uses the [ConfigureDCUcatalog.ps1](ConfigureDCUcatalog.ps1) script.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
