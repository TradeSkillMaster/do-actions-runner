FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN useradd -m actions
RUN apt-get -y update && apt-get install -y apt-transport-https ca-certificates curl wget jq software-properties-common \
    && toolset="$(curl -sL https://raw.githubusercontent.com/actions/runner-images/main/images/ubuntu/toolsets/toolset-2204.json)" \
    && common_packages=$(echo $toolset | jq -r ".apt.common_packages[]") && cmd_packages=$(echo $toolset | jq -r ".apt.cmd_packages[]") \
    && for package in $common_packages $cmd_packages; do apt-get install -y --no-install-recommends $package; done

RUN \
    RUNNER_VERSION="$(curl -s -X GET 'https://api.github.com/repos/actions/runner/releases/latest' | jq -r '.tag_name|ltrimstr("v")')" \
    && cd /home/actions && mkdir actions-runner && cd actions-runner \
    && wget https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R actions ~actions

RUN add-apt-repository ppa:git-core/ppa -y \
    && apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential git

# Install LTS Node.js and related build tools
RUN curl -sL https://raw.githubusercontent.com/mklement0/n-install/stable/bin/n-install | bash -s -- -ny - \
    && ~/n/bin/n lts \
    && npm install -g npm pnpm nx@latest \
    && rm -rf ~/n

# Install Docker
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

WORKDIR /home/actions/actions-runner

USER actions
COPY --chown=actions:actions entrypoint.sh .
RUN chmod u+x ./entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
