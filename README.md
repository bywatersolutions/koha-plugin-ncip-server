# NCIP server plugin for Koha

This plugin implements an NCIP server for Koha on top of Koha's REST API.

It is the successor to, and a full replacement for, the standalone
[ncip-server](https://github.com/bywatersolutions/ncip-server) application,
which is being archived. There is no separate service to deploy, proxy, or
upgrade alongside Koha anymore. Install the plugin, configure it, and point
your NCIP partners at the endpoint.

The plugin implements the same NCIP services as the standalone server:
LookupUser, LookupItem, LookupVersion, CheckOutItem, CheckInItem, RenewItem,
RequestItem, CancelRequestItem, AcceptItem, and DeleteItem, for NCIP v2 (with
partial v1 support for LookupUser, CheckOutItem, CheckInItem, AcceptItem, and
RequestItem).

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

After installing or upgrading the plugin, restart your Koha services. The API
route is merged into Koha's REST API at startup, so it will not exist until
after a restart. Configuration changes do not need a restart.

## The endpoint

All NCIP messages are POSTed to a single endpoint, the message type is read
from the XML body:

```
POST /api/v1/contrib/ncip_server/ncip
POST /api/v1/contrib/ncip_server/ncip/{auth_token}
```

The NCIP XML can be sent as the raw request body, or as a form field named
`xml` or `XForms:Model` (for older clients).

A GET request to the same URLs returns an empty NCIP envelope containing
`It works!`, like the standalone server did, which is handy for checking from a
browser that the endpoint is up.

Notes:

- Do not add query string parameters to the URL. Koha's REST API rejects
  undeclared query parameters with a 400 error.
- There is no `/health` endpoint. Monitor Koha itself instead.
- On Koha 26.05 and later, a request sent with a `Content-Type:
  application/xml` header will have its body converted to JSON by Koha's REST
  API (Bug 37762) before the plugin sees it, which breaks the message. Have
  clients send `text/xml`, or normalize the header in Apache (see below).

### Keeping the old /ncip URLs working

Deployments migrating from the standalone server can keep their partners'
existing URLs by adding a mapping to the Apache vhost that serves Koha's API
(usually the OPAC vhost):

```apache
RewriteEngine on
RewriteRule ^/ncip/?$    /api/v1/contrib/ncip_server/ncip      [PT,L]
RewriteRule ^/ncip/(.+)$ /api/v1/contrib/ncip_server/ncip/$1   [PT,L]

# Recommended on Koha 26.05 and later, see the note about Bug 37762 above
<LocationMatch "^/ncip">
    RequestHeader set Content-Type "text/xml"
</LocationMatch>
```

## Configuration

The plugin is configured with a YAML document on the plugin's configuration
page. The top level holds the authentication settings, and the `koha:` block
holds the NCIP behavior settings, the same block the standalone server used
in its `config.yml`, so an existing configuration can be pasted in verbatim.

```yaml
---
auth_token: XXX
token_required: true
koha:
  userenv_borrowernumber: 42
  framework: 'FA'
  lookup_user_id: 'cardnumber'
  trap_hold_on_accept_item: 1
```

### Authentication

| Key | Description |
| --- | --- |
| `token_required` | If true, requests must include the token in the URL (`.../ncip/{auth_token}`). Requests without a matching token get a 403. |
| `auth_token` | The token to require. |

If you are migrating from the standalone server, the `NcipRequireToken` and
`NcipToken` system preferences it used are migrated into these keys
automatically when the plugin is installed, and the preferences are deleted.

### The koha block

| Key | Default | Used by | Description |
| --- | --- | --- | --- |
| `userenv_borrowernumber` | none (required) | all writes | Borrowernumber of the librarian to act as. Best practice is to create an "NCIP Librarian" account. |
| `framework` | `FA` | AcceptItem | Framework for records created by AcceptItem. |
| `item_branchcode` | pickup branch | AcceptItem | Force created items to a given home/holding branch. The special value `__PATRON_BRANCHCODE__` uses the requesting patron's branch. |
| `always_generate_barcode` | 0 | AcceptItem | Always generate a new barcode, even if the requested barcode is unused. |
| `barcode_prefix` | none | AcceptItem | Prefix added to incoming barcodes. |
| `no_error_on_return_without_checkout` | 0 | CheckInItem | Return success instead of an error when checking in an item with no checkout. |
| `trap_hold_on_accept_item` | 0 | AcceptItem | Trap the hold at accept time (set it waiting or in transit). |
| `trap_hold_on_checkin` | 0 | CheckInItem | Trap the hold at checkin time instead. Implies `no_error_on_return_without_checkout`. |
| `itemtype_map` | none | AcceptItem | Map of `ItemOptionalFields/Format` values to Koha itemtypes. |
| `replacement_price` | none | AcceptItem | Replacement price for created items. |
| `item_callnumber` | none | AcceptItem | Callnumber used when the message has no `ItemDescription/CallNumber`. |
| `item_itemtype` | none | AcceptItem | Fallback itemtype for created items. |
| `item_ccode` | none | AcceptItem | Collection code for created items. |
| `item_location` | none | AcceptItem | Shelving location for created items. |
| `do_not_include_user_identifier_primary_key` | 0 | LookupUser | Don't send the borrowernumber in a UserId block. |
| `user_id_lookup_field` | none | all lookups | Search this borrowers column for the user id instead of cardnumber/userid (e.g. `sort1`). |
| `lookup_user_id` | `cardnumber` | LookupUser | Which id to send back: `cardnumber`, `userid`, `borrowernumber`, or `same` (echo whatever id was sent). |
| `request_identifier_value_as_barcode` | 0 | AcceptItem | Use `RequestId/RequestIdentifierValue` as the barcode instead of `ItemId/ItemIdentifierValue`. |
| `format_ValidToDate` | `%Y-%m-%d` | LookupUser | strftime format for `UserPrivilege/ValidToDate`. The NCIP spec calls for `%Y-%m-%dT%H:%M:%S`. |
| `format_DateDue` | `%Y-%m-%dT%H:%M:%S` | CheckOutItem | strftime format for `DateDue`. |
| `suppress_in_opac` | none | AcceptItem | Set to 1 to hide records created via AcceptItem from OPAC search results. |
| `ignore_item_requests` | 0 | RequestItem | Don't create holds for RequestItem messages, just return success. |
| `deny_duplicate_barcodes` | 0 | AcceptItem | Reject AcceptItem messages whose barcode already exists instead of generating a new one. |
| `accept_item_title_prefix` | none | AcceptItem | Word or phrase prepended to titles of records created via AcceptItem. |
| `delete_item_on_checkin` | 0 | CheckInItem | Act as if DeleteItem had been called directly after a checkin. |
| `delete_item_on_checkin_itemtype` | none | CheckInItem | Limit that deletion to this itemtype. |
| `delete_item_on_checkin_homebranch` | none | CheckInItem | Limit that deletion to this homebranch. |
| `delete_item_on_checkin_holdingbranch` | none | CheckInItem | Limit that deletion to this holdingbranch. |

## Testing

The test suite runs inside [koha-testing-docker](https://gitlab.com/koha-community/koha-testing-docker).
It needs the `XML::Hash` module, which is not a Koha dependency:

```
cpanm --notest XML::Hash
cd /kohadevbox/koha
prove -r /var/lib/koha/kohadev/plugins/t
```
