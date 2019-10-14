---
title: "Building a Docker X11 Desktop Environment"
description: "I cover how and why I built an immutable workstation X11 environment running inside a Docker container"
date: 2019-10-14
tags: ["docker", "workstation", "linux"]
---

# The #immutable dream

I've always loved the idea of having an immutable workstation (with the exception of data storage of course :stuck_out_tongue_closed_eyes:). A PC where you can just blow it away by rebooting and you are back to a known-working state. I've looked into many options like VM's or one-off scripts to install everything - even products like [Deep Freeze](https://deepfreeze.com.au/) - but nothing suited all my needs.

# What I wanted

In order of importance

* Simple setup - no stuffing around with arguments or variables every time I want to rebuild it
* High performance
* Volumes mapped to my persistent storage drives automatically
* Semi-recent versions of applications installed
* Easy to make persistent changes to the image when required
* Decent looking desktop and GUI theme - no Windows 95/98-esque action here please

# Docker to the rescue?

I've wondered for some time now whether it would be possible to get a headless X11 desktop working in Docker.

I initially searched around in 2018, but couldn't find anything at the time (probably a dodgy search effort on my behalf :man_facepalming:). Then I saw [something on Hacker News](https://github.com/bewster/debian-vnc-desktop-docker) that piqued my interest, lo and behold, it had what I was looking for.

# Building it

I took a lot of inspiration from [here](https://github.com/ConSol/docker-headless-vnc-container/blob/master/Dockerfile.ubuntu.xfce.vnc) to find out how to build the container - I decided not to use that image as a base as I wanted more recently up-to-date software.

I also found this [repo here](https://github.com/mikadosoftware/workstation) and looked at how they had setup X11 forwarding from the container.

As I wanted up to date software, I chose Ubuntu 19.04 as the base image (19.10 is coming soon!)

```dockerfile
FROM ubuntu:19.04
```

I then defined some variables that can be used across services in the container and also the Dockerfile whilst building

```dockerfile
ENV VNC_PORT=5901 \
    VNC_RESOLUTION=1024x640 \
    DISPLAY=:1 \
    TERM=xterm \
    DEBIAN_FRONTEND=noninteractive \
    HOME=/home/user \
    PATH=/opt/TurboVNC/bin:$PATH \
    SSH_PORT=22

EXPOSE $VNC_PORT
EXPOSE $SSH_PORT
```

Then I installed the shared utilities that are used across the system and are required by X11, SSH and the VNC server. The process to find these out was trial and error - install an application (like VNC), see if it has an error when running, and then install one of these packages where required.

```dockerfile
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        apt-utils \
        ca-certificates \
        locales \
        net-tools \
        sudo \
        supervisor \
        wget \
        openssh-server
```

If you are new to Docker and Ubuntu, the `--no-install-recommends` is a great argument for `apt-get` as it trims off any optional libraries or utilities that come by default with many packages which really helps to reduce your image layer size.

I chose to use XFCE4 as my window manager as it is frequently updated, comes with a decent modern looking theme, and is also lightweight - it is also possible with a small effort to use LXDE or GNOME.

```dockerfile
RUN apt-get install -y --no-install-recommends \
        dbus-x11 \
        libexo-1-0 \
        x11-apps \
        x11-xserver-utils \
        xauth \
        xfce4 \
        xfce4-terminal \
        xterm
ENV TVNC_WM=xfce4-session
```

Setting the `TVNC_WM` environment variable makes sure that our VNC server of choice (TurboVNC, hence `TVNC_WM`) uses XFCE4 as our default window manager when starting a VNC session.

I chose to use TurboVNC as it is one of the most featured VNC servers available for Linux that is free and open source. It supports many things like clipboards, drag and drop, audio and even OpenGL acceleration (if your Docker host supports it).

```dockerfile
ENV TVNC_VERSION=2.2.2
RUN export TVNC_DOWNLOAD_FILE="turbovnc_${TVNC_VERSION}_amd64.deb" && \
    wget -q -O $TVNC_DOWNLOAD_FILE "https://sourceforge.net/projects/turbovnc/files/2.2.2/${TVNC_DOWNLOAD_FILE}/download" && \
    dpkg -i $TVNC_DOWNLOAD_FILE && \
    rm -f $TVNC_DOWNLOAD_FILE
```

Next I configured the SSH server to enable X11 forwarding from localhost by default.

```dockerfile
RUN mkdir -p /var/run/sshd
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config && \
    sed -ri 's/^#AllowTcpForwarding\s+.*/AllowTcpForwarding yes/g' /etc/ssh/sshd_config && \
    sed -ri 's/^#X11Forwarding\s+.*/X11Forwarding yes/g' /etc/ssh/sshd_config && \
    sed -ri 's/^#X11UseLocalhost\s+.*/X11UseLocalhost no/g' /etc/ssh/sshd_config
```

Now I added another user account named `user` that also has sudo privileges. This is so that I don't have to use the root account during normal day-to-day operation. I also disabled the password requirement when running `sudo` as it pains me (insecure I know, but I can blow this machine away if anything bad happens). Then the working directory gets set to the new user home directory.

```dockerfile
RUN useradd -ms /bin/bash user && \
    adduser user sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER user
WORKDIR $HOME
```

Then I created the VNC config directory and made an empty Xauthority file - X11 and VNC can't create this file upon startup or when a new connection comes in.

```dockerfile
RUN touch ~/.Xauthority && \
    mkdir ~/.vnc
```

Finally I copied in the startup Bash script and made it executable and set it as the Docker entrypoint.

```dockerfile
COPY home/ $HOME/

COPY start.sh /startup/start.sh
RUN sudo chmod +x /startup/start.sh

ENTRYPOINT [ "/startup/start.sh" ]
CMD [ "--wait" ]
```

Below you can see the startup Bash script which is performing a few tasks before it finally starts waiting for infinity (it never comes ;)).

1. First it sets the user account and VNC passwords to those passed in using the `PASSWORD` environment variable.

    This is done in the startup script so that we can override it when starting up the container - if we were to set this when building the container, we would be unable to override it at runtime without rebuilding the image.

2. It then overrides the permissions for any launcher icons on the desktop to make them executable.

    I also chose to put this in the startup script so that if anyone extends the Docker image using it as the base of their image, any extra icons they copy in will also get the permissions updated at container launch.

3. Then it starts the SSH server and VNC server.

4. Finally it waits for infinity (or a `Ctrl+C`) if the default `--wait` command is passed in. This is required so the Docker container doesn't immediately die.

    Alternatively, if a custom command is passed in when starting the container, that will be run instead. This can be handy if you want a quick temporary execution environment and it can be blown away when it's finished.

```bash
#!/bin/bash
set -e

# Set the password
PASSWD_PATH="$HOME/.vnc/passwd"
echo "user:$PASSWORD" | sudo chpasswd
echo "$PASSWORD" | vncpasswd -f >> $PASSWD_PATH && chmod 600 $PASSWD_PATH

# Apply permissions
sudo find $HOME/ -name '*.desktop' -exec chmod $verbose a+x {} +

# Startup the SSH server
sudo /usr/sbin/sshd

# Startup the VNC server
vncserver $DISPLAY -nohttpd -depth 32 -geometry $VNC_RESOLUTION -name "Ubuntu VNC"

if [ -z "$1" ] || [[ $1 =~ -w|--wait ]]; then
    echo -e "Waiting for VNC server to exit"
    wait
else
    echo -e "Executing '$@'"
    exec "$@"
fi
```

If you aren't familiar with using a pass-through Bash script as your container entrypoint, it is a great way to build containers for a few reasons:

* You have a central place to apply once-off runtime configuration when starting the container

* When using `docker run` commands like

    ```bash
    docker run -it ubuntu-vnc /bin/bash
    ```

    your pass-through script will still get executed first as it is the entrypoint, then the `exec "$@"` will execute the initial command `/bin/bash`

* You can run initial startup sanity checks if required and exit the container early

* If anyone wants to extend your container, they can either overwrite your entrypoint script and provide the same pass-through functionality, or they can create an additional script, and call the original at the end of theirs.

# Starting it up

Now that the container is built it was time to start it up.

As I use VS Code to write the Dockerfile, scripts and config, I made a set of VS Code tasks to handle common `docker-compose` commands. This makes it really easy from VS Code to build and startup the container.

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "docker-compose-build",
            "type": "shell",
            "command": "docker-compose -f docker-compose.yml build",
            "args": [],
            "problemMatcher": []
        },
        {
            "label": "docker-compose-up",
            "type": "shell",
            "command": "docker-compose -f docker-compose.yml down && docker-compose -f docker-compose.yml up",
            "args": [],
            "problemMatcher": []
        },
        {
            "label": "docker-compose-down",
            "type": "shell",
            "command": "docker-compose -f docker-compose.yml down",
            "args": [],
            "problemMatcher": []
        }
    ]
}
```

If using the command line, just run the following command from the project root directory.

```bash
docker-compose build
```

Once the build is complete, run

```bash
docker-compose up
```

This starts up the container and should output some logs as the VNC server is started up. Once it outputs `Waiting for VNC server to exit` the container is ready to go.

# Connecting

The ideal way to connect to the container is by using X11 Forwarding over SSH. This integrates with your normal desktop environment by forwarding the windows through to your host desktop. If you are on Mac, you will need an X11 Server like XQuartz to get this working.

To connect to the container using SSH, run

```bash
ssh -Y user@localhost -p 2222
```

the default password is `password`.

After connecting to the container, it is now possible to run programs from within the SSH session and they will automatically open up on your host desktop appearing just as every other application.

As an example, try running `xeyes` or `xclock`.

If those are working, try out `firefox` or `sublime` - both should popup on your desktop, just like the native versions for your host OS.

It is also possible to connect to the container using VNC. This is great if something isn't quite working, or if you want the full Linux desktop experience. To connect to VNC, use `localhost:5901` as the hostname when connecting from your chosen VNC client.

# Summing up

Overall, I am pretty happy with how this turned out. It is great having a reliable and reproducible machine to work with when required.

It is especially handy when you want to run a jump-host or bastion in a cloud environment. With this, there is no need to run a dedicated box running a full GUI OS, you can just have another Docker server in the jump-host network - even running multiple workstations if you like!

The only pain point I have found so far is that running the Docker host on Mac or Windows can be a little laggy, especially when watching videos in the web browser. This is mainly due to Mac and Windows requiring a VM to run Docker inside of. The side effect of this is that OpenGL support is non-existant (which really helps for modern video playback and web browsers).

If you are interested in using the end product, [check it out here](https://github.com/drjaydenm/docker-headless-vnc). If you extend upon it, or have any ideas for improvements, I would love to hear them.