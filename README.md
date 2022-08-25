## What

Run [erpnext](https://www.erpnext.com/) on [Cloudron](https://cloudron.io)

## Why

Because, why not?

## Build and Install

- Install Cloudron CLI on your machine: `npm install -g cloudron-cli`.
- Install Docker, and make sure you can push to docker hub, or install the docker registry app in your own Cloudron.
- Log in to your Cloudron using cloudron cli: `cloudron login <my.yourdomain.tld>`.
- Build and publish the docker image: `cloudron build`.
- If you're using your own docker registry, name the image properly,
  like `docker.example-cloudron.tld/john_doe/cloudron-erpnext`.
- Log in to Docker Hub and mark the image as public, if necessary.
- Install the app `cloudron install -l <erp.yourdomain.tld>`
- Look at the logs to see if everything is going as planned.

Refer to the [Cloudron Docs](https://docs.cloudron.io/packaging/cli) for more information.

## About dev-scripts

Please refer to `docker-run.sh` file for some commands handy for you to test this setup.

## LDAP Connection [WIP]

LDAP Auth is already configured. When a user logs in for the first time, a new **System User** is created with **Guest**
role. An admin can then change the user's role.

LDAP Group sync or custom group mapping could also be possible, but I haven't tried it yet. Send a PR if you want.

For now, use the script `/app/code/setup-ldap.sh` and make necessary changes, then modify the LDAP settings to
suit your needs using the REST API, even if you have already completed setup.

## Updating ErpNext

This might not work yet because of the read-only
filesystem. [Official Documentation](https://frappeframework.com/docs/v14/user/en/production-setup#updating)

```shell
  # update everything
  bench update
  
  # update apps
  bench update --pull
  
  # run patches only
  bench update --patch
  
  # build assets only
  bench update --build
  
  # update bench (the cli)
  bench update --bench
  
  # update python packages and node_modules
  bench update --requirements
```

## Third-party Intellectual Properties

All third-party product names, company names, and their logos belong to their respective owners, and may be their
trademarks or registered trademarks.