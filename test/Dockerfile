# Dockerfile to test the library with multiple versions of PowerShell >= 7.
#
# Example run (from repo root):
# > $version="7.1.5"; docker build -f .\test\docker\Dockerfile . -t powershell-featureflags-test:$version --build-arg VERSION=$version --build-arg UBUNTU_VERSION=18.04 && docker run powershell-featureflags-test:$version

ARG VERSION=7.2.5
ARG UBUNTU_VERSION=16.04
FROM mcr.microsoft.com/powershell:${VERSION}-ubuntu-${UBUNTU_VERSION}

# Install dotnet SDK.
#
# Not using the dotnet SDK images because they bring their own powershell,
# see for example https://github.com/dotnet/dotnet-docker/blob/main/src/sdk/6.0/focal/amd64/Dockerfile.
ENV DOTNET_SDK_VERSION=6.0.301 
RUN curl -fSL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$DOTNET_SDK_VERSION/dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz
RUN mkdir -p /usr/share/dotnet
RUN tar -oxzf dotnet.tar.gz -C /usr/share/dotnet
RUN rm dotnet.tar.gz
RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

# Copy the application code.
WORKDIR /app
COPY . .

# Restore dependencies and run tests.
CMD pwsh tools/restore.ps1; pwsh tools/run-tests.ps1