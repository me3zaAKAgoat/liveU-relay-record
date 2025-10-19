FROM alpine:3.20

# Install mediaMTX
RUN wget https://github.com/bluenviron/mediamtx/releases/download/v1.15.2/mediamtx_v1.15.2_linux_arm64.tar.gz && \
    tar -xzf mediamtx_v1.15.2_linux_arm64.tar.gz && \
    mv mediamtx /usr/local/bin/ && \
    rm mediamtx_v1.15.2_linux_arm64.tar.gz

# Install required tools for the upload script and forwarding
RUN apk add --no-cache aws-cli curl bash findutils coreutils ffmpeg

# Copy scripts
COPY scripts/on_end.sh /usr/local/bin/on_end.sh
COPY scripts/forward.sh /usr/local/bin/forward.sh
RUN chmod +x /usr/local/bin/on_end.sh /usr/local/bin/forward.sh

# Copy config
COPY mediamtx.yml /mediamtx.yml

WORKDIR /

EXPOSE 1935 7001/udp 9997

CMD ["/usr/local/bin/mediamtx"]
