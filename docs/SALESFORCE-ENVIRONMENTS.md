# Salesforce Environments

## Product

Product Name: Who Sees What
Product Code: WSW
Repository: PermissionChecker
Environment Strategy: Dedicated Developer Edition Org

## Development Org

Environment: Development
Org Type: Developer Edition

CLI Alias: wsw-dev
Username: ishann.tforce.a3cd5122e44a@agentforce.com
Org ID: 00DgK00000a8MoDUAU

Purpose:
Primary development environment for Who Sees What.

## Local Project

Repository:
D:\Product\PermissionChecker\PermissionChecker

Project Target:
wsw-dev

Command to verify:

sf config get target-org --verbose
sf org display

## Important

This Salesforce org is dedicated to the Who Sees What product.

Do not deploy metadata belonging to:

- Mass Delete
- Google Form Auto Sync
- Smart Lookup Data Loader
- Accounting
- Other TwinStack products

## Security

Never store the following in this repository:

- Salesforce password
- Security token
- Access token
- Refresh token
- SFDX Auth URL
- Connected App consumer secret
- JWT private key