### letsencrypt-nginx-proxy-companion test suite

The test suite can be run locally on a Linux or macOS host.

To prepare the test setup:

```bash
git clone https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion.git
cd docker-letsencrypt-nginx-proxy-companion
test/setup/setup-local.sh --setup
```

Then build the docker image and run the tests:

```bash
docker build -t jrcs/letsencrypt-nginx-proxy-companion .
test/run.sh jrcs/letsencrypt-nginx-proxy-companion
```

You can limit the test run to specific test(s) with the `-t` flag:

```bash
test/run.sh -t docker_api jrcs/letsencrypt-nginx-proxy-companion
```

When running the test suite, the standard output of each individual test is captured and compared to its expected-std-out.txt file. When developing or modifying a test, you can use the `-d` flag to disable the standard output capture by the test suite.

```bash
test/run.sh -d jrcs/letsencrypt-nginx-proxy-companion
```

To remove the test setup:

```bash
test/setup/setup-local.sh --teardown
```
