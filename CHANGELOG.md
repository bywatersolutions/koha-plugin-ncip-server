# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-23

### Added

- The token URL can now end in `/ncip`
  (`/api/v1/contrib/ncip_server/ncip/{auth_token}/ncip`), for ILL systems such
  as Rapido that add `/ncip` to the end of the address they are given.

### Changed

- The configuration page now uses Koha's standard plugin page layout, with
  the administration breadcrumbs and sidebar.

### Fixed

- A request carrying the wrong token is now rejected even when
  `token_required` is off, matching the standalone NCIP server.
- A RequestItem that gives only an item identifier now places an item level
  hold on that item.
- AcceptItem no longer adds an empty author (100) field to the brief record
  when the request has no author.

## [0.0.1] - 2026-09-08

### Added

- Initial version of the NCIP server as a Koha plugin. This plugin replaces the
  standalone [ncip-server](https://github.com/bywatersolutions/ncip-server)
  application. NCIP messages are served through Koha's plugin REST API at
  `/api/v1/contrib/ncip_server/ncip`, configuration lives in the plugin's
  configuration page, and the legacy `NcipRequireToken` / `NcipToken` system
  preferences are migrated into the plugin configuration on install.
