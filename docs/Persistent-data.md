## Persistent data

### Anonymous volumes

When you follow instructions from Basic usage or Advanced usage, Docker will automatically create **anonymous volumes** (volumes with a random name) for every `--volume` / `-v` argument passed:

```shell
$ docker run -d \
    --name nginx-proxy \
    -p 80:80 \
    -p 443:443 \
    -v /etc/nginx/certs \
    -v /etc/nginx/vhost.d \
    -v /usr/share/nginx/html \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    jwilder/nginx-proxy

$ docker volume ls
DRIVER              VOLUME NAME
local               287be3abd610e5566500d719ceb8b952952f12c9324ef02d05785d4ee9737ae9
local               6530b1b40cf89efb71aa7fd19bddec927fa2bcae59b04b9c1c850af72ffe0123
local               f260f71fefadcdfc311d285d69151f2312915174d3fb1fab89949ec5ec871a54
local               f2cd94ca48904dc9cfc840ce4b265a04831c580d525253d7a0e5aac4d1dca340
```

### Named volumes (recommended)

Using **named volumes** instead make managing volumes easier:

```shell
$ docker run -d \
    --name nginx-proxy \
    -p 80:80 \
    -p 443:443 \
    -v certs:/etc/nginx/certs \
    -v vhost:/etc/nginx/vhost.d \
    -v html:/usr/share/nginx/html \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    jwilder/nginx-proxy

$ docker volume ls
DRIVER              VOLUME NAME
local               certs
local               vhost
local               html
```

### Host volumes

Alternatively, you might want to store the certificates on a local folder rather than letting Docker create and manage a volume for them. This is easily achieved by using a **host volume** (binding an absolute path on your host to the `/ect/nginx/certs` folder on your containers):

`-v /path/to/certificates:/etc/nginx/certs`

No matter the type of volume you choose, if you set them on the nginx-proxy or nginx container and use `--volumes_from` on the others containers, they will automatically be mounted inside the container to the path your first defined.

### Restraining other containers write permission

If you want to restrain the **nginx** and **docker-gen** processes to read only access on the certificates, you'll have to use different volume flags depending on the container.

Example with named volumes:

`-v certs:/etc/nginx/certs:ro` on the **nginx-proxy** or **nginx** + **docker-gen** container(s).

`-v certs:/etc/nginx/certs:rw` on the **letsencrypt-nginx-proxy-companion** container.

## Ownership & permissions of private and ACME account keys

By default, the **letsencrypt-nginx-proxy-companion** container will enforce the following ownership and permissions scheme on the files it creates and manage:

```
[drwxr-xr-x]  /etc/nginx/certs
├── [drwxr-xr-x root root]  accounts
│   └── [drwxr-xr-x root root]  acme-v02.api.letsencrypt.org
│       └── [drwxr-xr-x root root]  directory
│           └── [-rw-r--r-- root root]  default.json
├── [-rw-r--r-- root root]  dhparam.pem
├── [-rw-r--r-- root root]  default.crt
├── [-rw-r--r-- root root]  default.key
├── [drwxr-xr-x root root]  domain.tld
│   ├── [lrwxrwxrwx root root]  account_key.json -> ../accounts/acme-v02.api.letsencrypt.org/directory/default.json
│   ├── [-rw-r--r-- root root]  cert.pem
│   ├── [-rw-r--r-- root root]  chain.pem
│   ├── [-rw-r--r-- root root]  fullchain.pem
│   └── [-rw-r--r-- root root]  key.pem
├── [lrwxrwxrwx root root]  domain.tld.chain.pem -> ./domain.tld/chain.pem
├── [lrwxrwxrwx root root]  domain.tld.crt -> ./domain.tld/fullchain.pem
├── [lrwxrwxrwx root root]  domain.tld.dhparam.pem -> ./dhparam.pem
└── [lrwxrwxrwx root root]  domain.tld.key -> ./domain.tld/key.pem
```

This behavior can be customized using the following environment variable on the **letsencrypt-nginx-proxy-companion** container:

* `FILES_UID` - Set the user owning the files and folders managed by the container. The variable can be either a user name if this user exists inside the container or a user numeric ID. Default to `root` (user ID `0`).
* `FILES_GID` - Set the group owning the files and folders managed by the container. The variable can be either a group name if this group exists inside the container or a group numeric ID. Default to the same value as `FILES_UID`.
* `FILES_PERMS` - Set the permissions of the private keys and ACME account keys. The variable must be a valid octal permission setting and defaults to `644`.
* `FOLDERS_PERMS` - Set the permissions of the folders managed by the container. The variable must be a valid octal permission setting and defaults to `755`.

For example, `FILES_UID=1000`, `FILES_PERMS=600` and `FOLDERS_PERMS=700` will result in the following:

```
[drwxr-xr-x]  /etc/nginx/certs
├── [drwx------ 1000 1000]  accounts
│   └── [drwx------ 1000 1000]  acme-v02.api.letsencrypt.org
│       └── [drwx------ 1000 1000]  directory
│           └── [-rw------- 1000 1000]  default.json
├── [-rw-r--r-- 1000 1000]  dhparam.pem
├── [-rw-r--r-- 1000 1000]  default.crt
├── [-rw------- 1000 1000]  default.key
├── [drwx------ 1000 1000]  domain.tld
│   ├── [lrwxrwxrwx 1000 1000]  account_key.json -> ../accounts/acme-v02.api.letsencrypt.org/directory/default.json
│   ├── [-rw-r--r-- 1000 1000]  cert.pem
│   ├── [-rw-r--r-- 1000 1000]  chain.pem
│   ├── [-rw-r--r-- 1000 1000]  fullchain.pem
│   └── [-rw------- 1000 1000]  key.pem
├── [lrwxrwxrwx 1000 1000]  domain.tld.chain.pem -> ./domain.tld/chain.pem
├── [lrwxrwxrwx 1000 1000]  domain.tld.crt -> ./domain.tld/fullchain.pem
├── [lrwxrwxrwx 1000 1000]  domain.tld.dhparam.pem -> ./dhparam.pem
└── [lrwxrwxrwx 1000 1000]  domain.tld.key -> ./domain.tld/key.pem
```

If you just want to make the most sensitive files (private keys and ACME account keys) root readable only, set the environment variable `FILES_PERMS` to `600` on your **letsencrypt-nginx-proxy-companion** container.
