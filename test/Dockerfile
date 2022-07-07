# syntax=docker/dockerfile:1
# Dockerfile to test the library with multiple versions of PowerShell >= 7.
#
# Example run (from repo root):
# PS > $version="7.1.5"; docker build -f .\test\docker\Dockerfile . -t powershell-featureflags-test:$version --build-arg VERSION=$version --build-arg UBUNTU_VERSION=18.04 && docker run powershell-featureflags-test:$version

ARG VERSION=7.2.5
ARG UBUNTU_VERSION=16.04
FROM mcr.microsoft.com/powershell:${VERSION}-ubuntu-${UBUNTU_VERSION}

# Install dotnet SDK.
#
# Not using the dotnet SDK images because they bring their own powershell,
# see for example https://github.com/dotnet/dotnet-docker/blob/main/src/sdk/6.0/focal/amd64/Dockerfile.
# For some reason, docker images for Powershell 6 don't have curl.
ENV DOTNET_SDK_VERSION=6.0.301 
RUN if ! command -v curl &> /dev/null; then apt-get update; apt-get install -y curl; fi \
    && curl -fSL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$DOTNET_SDK_VERSION/dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz \
    && mkdir -p /usr/share/dotnet \
    && tar -oxzf dotnet.tar.gz -C /usr/share/dotnet

FROM mcr.microsoft.com/powershell:${VERSION}-ubuntu-${UBUNTU_VERSION}
# Copy the dotnet installation.
COPY --from=0 /usr/share/dotnet /usr/share/dotnet
RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet
# Copy the application code.
WORKDIR /app
COPY . .

# Restore dependencies and run tests.
CMD pwsh tools/restore.ps1; pwsh tools/run-tests.ps1
