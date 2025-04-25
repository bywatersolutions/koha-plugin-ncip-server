# NCIP server plugin for Koha

This plugin implements an NCIP server for Koha.

## Installing

### Search and install

Add the following snippet in the `<plugin_repos>` section of your `koha-conf.xml` file:

```xml
<repo>
    <name>ByWater Solutions</name>
    <org_name>bywatersolutions</org_name>
    <service>github</service>
</repo>
```

After restarting your services (including `memcached`) you will be able to search for _ncip_ on the plugins
management page.

### Manual install

Download this plugin from the [Releases page](https://github.com/bywatersolutions/koha-plugin-ncip-server/releases) page.
