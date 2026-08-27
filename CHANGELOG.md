# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial version of the NCIP server as a Koha plugin. This plugin replaces the
  standalone [ncip-server](https://github.com/bywatersolutions/ncip-server)
  application. NCIP messages are served through Koha's plugin REST API at
  `/api/v1/contrib/ncip_server/ncip`, configuration lives in the plugin's
  configuration page, and the legacy `NcipRequireToken` / `NcipToken` system
  preferences are migrated into the plugin configuration on install.
