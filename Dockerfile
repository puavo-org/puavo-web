FROM debian:stretch
RUN apt-get update
RUN apt-get -y install systemd
CMD ["/lib/systemd/systemd"]
