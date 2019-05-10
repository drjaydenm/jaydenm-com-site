---
title: "SnowEngine"
date: 2012-02-25
status: "Complete"
description: "A game engine written from the ground up in C# using DirectX and OpenGL targeting Windows, OSX & Linux"
links: ["https://www.youtube.com/watch?v=5JApIUeIW0U"]
---

{{% figure src="snowengine.jpg" title="In-game screenshot" %}}

SnowEngine is a game engine that is written in C# utilising both DirectX on Windows and OpenGL on OSX/Linux. The aim of this project is to create the low and high level components of an engine to learn how everything works from cross-platform grahpics development right through to rendering techniques.

This project taught me a great deal of software architecture patterns due to the need of having generic interfaces to different platform specific rendering sub-systems like DirectX and OpenGL. I also utilised generics to assist in dealing with different types of game assets such as textures, models, shaders and animations using shared data structures.

I also learnt a lot about high performing code, threading and optimisation as the target frame rate for a game is 60FPS (frames per-second) giving just 16.66 milliseconds for all game logic to run.