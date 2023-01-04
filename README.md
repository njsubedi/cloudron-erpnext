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

## Logging in
Look for credentials in the file `<your-site-name>-credentials.txt` from the file manager.sd

## LDAP Connection [WIP]

LDAP Auth is not already configured. When a user logs in for the first time, a new **System User** is created with **
Guest** role. An admin can then change the user's role.

LDAP Group sync or custom group mapping could also be possible, but I haven't tried it yet. Send a PR if you want.

For now, look at the `/app/pkg/setup-ldap.sh` and make necessary changes. Run the command to add LDAP settings. The
script is configured to use your cloudron's LDAP addon.

- add : adds LDAP settings to the site
- disable: disables LDAP settings (required before deleting)
- delete: deletes the LDAP settings for the site

## Installing Apps

You can install new frappe apps. To install the apps, simply follow these steps, and restart the app.
Also refer to the [Official Documentation](https://frappeframework.com/docs/v14/user/en/bench/bench-commands#add-apps)

```shell
# Make sure you are in the /app/code/frappe-bench directory.
cd /app/code/frappe-bench

gosu cloudron bench get-app --branch <branch> <appname>
gosu cloudron bench install-app hrms

# Example: install the hrms app for HR Management
gosu cloudron bench get-app --branch v1.0.0 hrms
gosu cloudron bench install-app hrms

```

Note: Restart the app using the Restart button on top of the terminal, or simply run `supervisorctl restart all` to
ensure the apps are properly configured.

## Updating ErpNext

### Important Notes

- **MAKE SURE TO BACKUP BEFORE TRYING TO UPDATE. IF THE UPDATE FAILS, THE APP MAY STOP RESPONDING, AND YOU MAY LOSE
  DATA.**

- **Run the `git` and `bench` commands with `gosu cloudron` as the user `cloudron` instead of the root user.**'

- **Put the app in Recovery Mode from the dashboard before running updates and turn it off later.**

```shell
  # Put the app in maintenance mode
  gosu cloudron bench set-maintenance-mode on
  
  
  # Turn off maintenance mode
  gosu cloudron bench set-maintenance-mode off
```

### 1. Update with Cloudron CLI

You can update this package normally by pulling the latest version of this repository, then running `cloudron update`
and `cloudron update --app your-app-domain`. This is the safest way to update the app.

**After updating, make sure to run `gosu cloudron bench migrate` from the terminal while the app is running.**

### 2. Automatic updates with bench

Set the application to Recovery Mode. Then update normally. Refer to
the [Official Documentation](https://frappeframework.com/docs/v14/user/en/production-setup#updating)

```shell
  # switch frappe and erpnext app version to version-14
  gosu cloudron bench switch-to-branch version-14 frappe erpnext
  
  #if you have more apps, switch to the respective versions for those apps as well
  # gosu cloudron bench switch-to-branch version-xxx app1 app2 app3 ...
  
  # update frappe and all apps, then run migration
  gosu cloudron bench update
  
```

You can also run each steps one at a time as needed.

```shell
  # update apps
  gosu cloudron bench update --pull
  
  # run patches only
  gosu cloudron bench update --patch
  
  # build assets only
  gosu cloudron bench update --build
  
  # update bench (the cli)
  gosu cloudron bench update --bench
  
  # update python packages and node_modules
  gosu cloudron bench update --requirements
```

## Disable public website (eg. Dashboard as homepage)

From the sidebar, **Website** -> **Website Settings** -> **Landing Page (Home Page)** -> Set to **app** instead of **
home**.

## Third-party Intellectual Properties

All third-party product names, company names, and their logos belong to their respective owners, and may be their
trademarks or registered trademarks.