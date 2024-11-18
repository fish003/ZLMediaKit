FROM ubuntu:20.04 AS build
ARG MODEL
#shell,rtmp,rtsp,rtsps,http,https,rtp
EXPOSE 1935/tcp
EXPOSE 554/tcp
EXPOSE 80/tcp
EXPOSE 443/tcp
EXPOSE 10000/udp
EXPOSE 10000/tcp
EXPOSE 8000/udp
EXPOSE 8000/tcp
EXPOSE 9000/udp

# ADD sources.list /etc/apt/sources.list

RUN apt-get update && \
         DEBIAN_FRONTEND="noninteractive" \
         apt-get install -y --no-install-recommends \
         build-essential \
         cmake \
         git \
         curl \
         vim \
         wget \
         ca-certificates \
         tzdata \
         libssl-dev \
         gcc \
         g++ \
         gdb && \
         apt-get autoremove -y && \
         apt-get clean -y && \
         rm -rf /var/lib/apt/lists/*

# 安装和编译 FFmpeg
WORKDIR /opt/ffmpeg
RUN wget https://ffmpeg.org/releases/ffmpeg-4.4.tar.bz2 && \
    tar -xvjf ffmpeg-4.4.tar.bz2 && \
    cd ffmpeg-4.4 && \
    ./configure --enable-shared --enable-gpl --enable-libx264 --enable-libvpx --enable-openssl --enable-pic && \
    make -j$(nproc) && \
    make install

RUN mkdir -p /opt/media
COPY . /opt/media/ZLMediaKit
WORKDIR /opt/media/ZLMediaKit

# 3rdpart init
WORKDIR /opt/media/ZLMediaKit/3rdpart

RUN wget https://github.com/cisco/libsrtp/archive/v2.5.0.tar.gz -O libsrtp-2.5.0.tar.gz && \
    tar xfv libsrtp-2.5.0.tar.gz && \
    mv libsrtp-2.5.0 libsrtp && \
    cd libsrtp && ./configure --enable-openssl && make -j$(nproc) && make install

# 安装usrsctp库的依赖
RUN apt-get update && apt-get install -y autoconf automake libtool pkg-config git

# 下载并安装usrsctp库
RUN git clone https://github.com/sctplab/usrsctp.git && \
    cd usrsctp && \
    ./bootstrap && \
    ./configure --prefix=/usr && \
    make && \
    make install

#RUN git submodule update --init --recursive && \

RUN mkdir -p build release/linux/${MODEL}/

WORKDIR /opt/media/ZLMediaKit/build
RUN cmake -DCMAKE_BUILD_TYPE=${MODEL} -DENABLE_WEBRTC=true -DENABLE_FFMPEG=true -DENABLE_TESTS=false -DENABLE_API=false .. && \
    make -j $(nproc)

FROM ubuntu:20.04
ARG MODEL

# ADD sources.list /etc/apt/sources.list

RUN apt-get update && \
         DEBIAN_FRONTEND="noninteractive" \
         apt-get install -y --no-install-recommends \
         vim \
         wget \
         ca-certificates \
         tzdata \
         curl \
         libssl-dev \
         ffmpeg \
         gcc \
         g++ \
         gdb && \
         apt-get autoremove -y && \
         apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
        && echo $TZ > /etc/timezone && \
        mkdir -p /opt/media/bin/www

WORKDIR /opt/media/bin/
COPY --from=build /opt/media/ZLMediaKit/release/linux/${MODEL}/MediaServer /opt/media/ZLMediaKit/default.pem /opt/media/bin/
COPY --from=build /opt/media/ZLMediaKit/release/linux/${MODEL}/config.ini /opt/media/conf/
COPY --from=build /opt/media/ZLMediaKit/www/ /opt/media/bin/www/
ENV PATH /opt/media/bin:$PATH
CMD ["./MediaServer","-s", "default.pem", "-c", "../conf/config.ini", "-l","0"]
