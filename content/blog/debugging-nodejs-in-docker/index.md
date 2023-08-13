---
title: "Debugging Node.js in Docker with Hot Reload"
description: "In this post I cover how to setup VS Code to debug a Node.js application running inside a Docker container with hot reloading"
date: 2023-08-13
tags: ["nodejs", "javascript", "docker"]
header_image: "header.jpg"
---

I was recently working on a Node.js application and needed to debug a specific issue I was having. This application is hosted within a Docker container both locally and when running in production.

Usually if I am trying to resolve something quickly, I might just normally use `console.log()` to check that a value was what I expected. However this specific scenario had me stumped and I needed to go deeper.

I did the usual "just Google it" which came back with quite a few results. You may then be thinking "why write another blog post about this" then. To which I had the exact same thought. However I had quite a few issues getting their examples to "just work".

They were either missing part of the setup, or missing some of the required parameters to get everything working well. Some were also not targeted towards Docker, so they also were missing other parts of the picture. So I thought, hey, I'll document this so that I don't forget it in the future, and maybe also help out someone with the same problem I had.

Righto enough blabbing, let's get into the solution.

# Setting up Node.js to allow debugging

The first step is to setup Node.js to allow debug connections. This is done via a rather oddly named parameter called `--inspect`. I'm sure it makes sense to someone, however it isn't intuitive when you're just wanting to debug.

Regardless, this parameter requires an IP address to bind to. Because we're running inside Docker, we need to bind to the IP of the container, not localhost. You can do this by passing `0.0.0.0` as the IP, which will bind to all available IP addresses. This parameter also requires a port to be specified for the debug listener. The default for this port is `9229` so we'll use that in this example.

The command so far will look like `node --inspect=0.0.0.0:9229 src/index.js`

# Exposing the debug port in Docker

Node.js will now be looking for debug connections from a debugger. If you tried to connect to this now from your host OS, you wouldn't have any luck still. This is because the port `9229` needs to be exposed and mapped to the host OS from the container.

I'm using Docker Compose for my application, so that can be done via a port mapping under the `ports` section. You could also do that with the `docker run` command using `-p 9229:9229`.

This is what the `docker-compose.yml` file looks like so far. The `Dockerfile` being used for the build is just doing a `FROM node:18-bullseye` - nothing special there.

```yml
version: "3"
services:
  my-service:
    build: .
    volumes:
      - ./src/:/home/node/app/src
      - ./data/:/home/node/app/data
    ports:
      - "8080:8080" # HTTP port for web application
      - "9229:9229" # The new debug port we need to expose
    command: "node --inspect=0.0.0.0:9229 --nolazy src/index.js"
```

With the port mapped, you should now be able to connect to the Node.js application running within Docker.

The keen eyed will have noticed the `--nolazy` parameter being passed into the `node` command there. This is required if you would like your breakpoints to behave correctly. The V8 engine that Node.js uses internally will lazily evaluate JavaScript code by default. The `--nolazy` parameter disables this functionality and tells the V8 engine to parse all code upfront.

# Connecting the debugger

The text editor and debugger I am using is VS Code. To allow us to easily start and stop debugging, and get native integration into the editor, I'll make use of the `launch.json` file. This file lets you setup actions that can be triggered via the UI, like what happens when you click "Start Debugging".

If you don't already have a `launch.json` file inside your `.vscode` directory, create one now. This is what my `launch.json` file looks like.

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "attach",
      "name": "Attach to Node.js in Docker",
      "port": 9229,
      "restart": true,
      "localRoot": "${workspaceFolder}/src",
      "remoteRoot": "/home/node/app/src"
    }
  ]
}
```

The key parts of that config are the `port` which needs to match the port set earlier in the Node.js command, and the `localRoot`/`remoteRoot`. These root directories need to match their correct locations to ensure that the source code running in Node.js inside Docker matches what is on your local machine. Without these setup, line numbers and variable names might be intelligible.

If you go to the Debug menu in VS Code now, you should see an option to `Attach to Node.js in Docker`. Clicking this should connect the debugger and allow you to hit a breakpoint and inspect variables now.

# Hot reloading on code changes

You could stop there if you like, however I also wanted to get hot reloading working with debugging. This is the part where I struggled to find the right help online that mixed debugging and hot reloading together.

The first step with hot reloading is to ensure [nodemon](https://github.com/remy/nodemon) is installed in the Docker container. You can do this by placing a `npm install -g nodemon` command inside the `Dockerfile`. Now the `docker-compose.yml` file can be changed to reference `nodemon` instead of `node` to start the application.

Here's a snippet from the `command` parameter in the `docker-compose.yml` file.

```yml
command: "nodemon --inspect=0.0.0.0:9229 --nolazy src/index.js"
```

If you try that out inside Docker, your mileage may vary depending on your host OS. It turns out that on Windows and MacOS, file events aren't correctly propagated inside the Docker container (at the time of writing). This means the way that `nodemon` looks for changes to files using file events won't work correctly. To get around this limitation, we can tell `nodemon` to "poll" for file changes (basically just continually check the files). The `-L` flag is used for this. Why "L" you ask (I did at least 😄)? That is because `nodemon` classes polling as the "legacy" watch mode. This fixes the Docker host OS limitation, at the cost of slightly higher CPU usage.

The new `docker-compose.yml` file `command` looks like:

```yml
command: "nodemon --inspect=0.0.0.0:9229 -L --nolazy src/index.js"
```

# Handling shutdown elegantly

With the above command, debugging will work, and hot reloading will also be firing correctly. There was still one thing that I wanted to solve though, and that was how to tell `nodemon` to elegantly shutdown my application when reloading code. By default `nodemon` will send the `SIGUSR2` signal to your application, however `express` and other frameworks won't always handle this out of the box. You could add support for this signal in your application, however Docker will also not use this signal by default, so you're adding another edge case to handle in your application code.

What we can do though, is to tell `nodemon` to change the signal that it sends to terminate and restart the application. In this case, my application is already setup to handle `SIGTERM` which is used when normally killing an application using `Ctrl+C` on the command line. We can do this by using the `--signal` parameter to `nodemon`.

With this added, the final `docker-compose.yml` file looks like.

```yml
version: "3"
services:
  my-service:
    build: .
    volumes:
      - ./src/:/home/node/app/src
      - ./data/:/home/node/app/data
    ports:
      - "8080:8080" # HTTP port for web application
      - "9229:9229" # The new debug port we need to expose
    command: "nodemon --inspect=0.0.0.0:9229 --signal SIGINT -L --nolazy src/index.js"
```

With that final argument in place, everything should now be working reliably. 🤞

That concludes my journey of finding the right setup for debugging Node.js in Docker with hot reloading. I hope you found this post useful, and as always, if you have any thoughts on how to improve, please let me know.
