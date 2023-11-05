Cloudflare DNS Search 
=====================

```shell
Example: ./cloudflare-dns-search.sh  -v -a "${CF_TOKEN}" -s alb.aws.com
Usage: ./cloudflare-dns-search.sh
   OPTIONS
   [ -a  CF_API_TOKEN (REQUIRED) Cloudflare API Token ]
   [ -s  (REQUIRED) Pass search term for this match. (Uses jq.contain()) ]
   [ -c  Set option to clears all cache ]
   [ -v  Set option to enable verbose output ]


++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
This script is used to identify Cloudflare DNS Records that match your search term.
CF does not support any global searching across accounts or even just for the look up type.
WARNING: Initial cache build may be really slow; CF will throttle the API if you have a large set of zones and records.

- @Dependencies: jq
- @Cacheing: Zones and Zone Record results are cached by default to ensure faster subsequent usage.
- @Access Cloudflare API access is required.
- [Create an "API Token"](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
		- Permissions: "Zone.Zone, Zone.DNS", "Read Only"
		- Resources: "All Zones"

```

Dependencies
------------
- [jq](https://devdocs.io/jq/) 

Cacheing 
---------
- Zones and Zone Record results are cached by default to ensure faster subsequent usage.

Access Cloudflare API access is required
----------------------------------------
- [Create an "API Token"](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
	- Permissions: "Zone.Zone, Zone.DNS", "Read Only"
	- Resources: "All Zones"