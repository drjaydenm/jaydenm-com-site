---
title: "Migrating .NET Framework Applications to .NET Core (Part 1)"
description: "This post gives a rough guide of how you may go about migrating a .NET Framework application to .NET Core along with some helpful tips and tricks"
date: 2020-03-06
tags: ["dotnet", "c#"]
header_image: "header.jpg"
---

# What I'll cover in the series

I'm sure everyone in the .NET ecosystem has heard of .NET Core now, and most people have at least given it a little go.

If you are part of a team that owns any .NET Framework applications, the question will no doubt have been raised of can/when/should we migrate to .NET Core?

Microsoft has [some articles](https://devblogs.microsoft.com/dotnet/porting-to-net-core/) and [documentation on migrating](https://docs.microsoft.com/en-us/dotnet/core/porting/), however I found detailed information on the process and the various gotchas hard to come by, so I thought it would be worth sharing my own experiences.

This is by no means a comprehensive guide that will cover every scenario, or something that I am advocating that you should follow. It is simply the process I would follow personally given what I know now, and has been refined after having migrated multiple applications from .NET Framework to Core.

# Posts in the series

I'm planning on making this a two part series as I found most tasks fit into one of these buckets:

1. Planning & Pre-migration
1. Migrating & Modernising

Keep on reading for more detail on why I've split it up into these 4 phases.

# Why migrate from .NET Framework to .NET Core

Some of you may be wondering why it is worth migrating at all, or perhaps you are having trouble convincing business stakeholders why it is important to do so. These are some of the advantages that really stand out to me:

- .NET Core runs cross platform (Linux/Windows/Mac). With containers being a popular choice these days, migrating gives you Linux support out of the box - no need for Mono on Linux anymore.
- Develop on all [common desktop OS's](https://github.com/dotnet/core/blob/master/release-notes/3.1/3.1-supported-os.md). This can really help developers if you have development PC's running different OS's as they can avoid running Windows VM's.
- Modern C# styles (more builder patterns and interfaces) - .NET Core removes quite a lot of the static classes that were prevalent in .NET Framework, particularly with ASP.NET such as the `HttpContext` class, giving you a more standardised approach.
- 1st party DI and host builder - A lot of common tools in .NET applications such as dependency injection, service hosting, logging and test integrations are provided almost out of the box with 1st party support from Microsoft packages
- Improved performance - the .NET Core CLR is where Microsoft is spending their time these days, and that means there has been massive improvements in performance as a result. Classic examples are the introduction of `Span<T>`, `ArrayPool<T>`, `MemoryPool<T>` and the `System.Numerics` namespace which gives access to SIMD operations on vectors and matrices (great for game/graphics development). There are many more general improvements that you can [read about here](https://devblogs.microsoft.com/dotnet/performance-improvements-in-net-core-2-1/).

# Isn't .NET 5 coming out soon anyway though?

.NET 5 is targeted at being released towards the end of 2020 which isn't too far away now. I have spoken to a few people who were misled by the naming change of dropping "Core" and going solely with .NET 5.

Some thought that .NET 5 meant there will either be refactors like are involved with migrating from .NET Framework to .NET Core, or that the environment may shift back towards .NET Framework styles slightly.

Microsoft has some great blog posts around the [plans for .NET 5](https://devblogs.microsoft.com/dotnet/introducing-net-5/) and also on the [future of .NET being based upon .NET Core](https://devblogs.microsoft.com/dotnet/net-core-is-the-future-of-net/). If you read both of these, it is clear that migrating to .NET Core now, gives you the easiest migration path to .NET 5 in the future.

It is also outlined in those posts, that .NET Framework 4.8 is the last release that will have any new features - from that point on, there will only be security fixes. If you would like to take advantage of most of the improvements I listed before, you aren't going to get them in .NET Framework.

# The high level process

Earlier in this post, I mentioned there were four main parts I've observed to the .NET Core migration process. I'll briefly outline these here:

1. Planning - This is mainly focused around estimating what work will be required upfront, and allowing you to more accurately estimate the timeline of the project. This can be done by looking at your project structure, packages in use, legacy features in use, CI/CD pipeline support and target environment support.
    
1. Pre Migration - This part involves carrying out some migration work that doesn't effect the deliverability of your application whilst in progress, but is required none-the-less to migrate to .NET Core. It involves migrating projects to .NET Standard, upgrading packages and removing/replacing legacy features. This puts you in the best position to start the actual migration.

1. Migrating - This is the biggest part of the project and will reach a point where you just have to “go all in”. If you have a project with multiple deployable units (e.g. an API and a worker service) it may be possible to migrate them one at a time. But keep an eye on any shared dependencies here - anything that relies on Framework or Core instead of .NET Standard could catch you out.
    
1. Modernisation - After you’ve put all the effort in to migrate the application, there is some extra work you can do to best take advantage of .NET Core. This involves moving to the latest configuration format, using Microsoft’s DI package, host builder and more.

# Planning

Now that we have covered the "why", lets get started on the first step of the process, planning.

## Project Structure

The first thing that is worth looking at is your overall project structure. You can run into issues in particular scenarios if you don't take a careful look upfront.

One thing in particular to watch out for is any shared references in projects. This is totally OK in the case of shared libraries (as long as they are .NET Standard compatible), but some edge cases can cause issues. One such scenario looks like this:

> `App.Worker` is a .NET Framework service worker. `App.Api` is a .NET Framework ASP.NET API. At a solution level, there is another project `App.Tests`, that references both `App.Worker` and `App.Api` for purposes of doing system wide testing (spins up the worker and API and runs them alongside each other). The catch here is that you cannot upgrade the `App.Api` or `App.Worker` projects to .NET Core one by one as the reference in the `App.Tests` project will cause issues as .NET Framework and .NET Core aren't backwards compatible with each other.

There are ways to fix this situation. The first is to split up the test project into two projects, one which tests that the API works, the other to test the worker functions correctly.

Another way to fix this is to split the worker up into two projects, one which contains all the business logic and is .NET Standard, and another that contains the runtime implementation which could be .NET Core. Then the tests can reference the business logic component only, which would resolve this issue here.

## NuGet Packages

Once you are confident that your project structure will play nicely with a staged .NET Core migration approach, you can start to look at the NuGet packages that are in use. I find the best approach here is to come from the angle of "what can't we upgrade to the latest version?". Upgrading to the latest version will generally give you the best chance of supporting .NET Core/Standard and also will probably have an API surface that is more similar to other .NET Core API's.

By the end of this process, you should have answers to the following questions:

- Are all the NuGet packages we currently use compatible with .NET Core/Standard?
- Which packages aren't up to date?
- Which out of date packages have breaking changes that require refactoring of code to support .NET Core/Standard?
- Which packages don't have support for .NET Core/Standard at all?

The last two points are the main areas to watch out for. NuGet updates which require refactoring can consume a vast amount of time, and block the .NET Core migration from starting altogether. Starting the migration with this in mind is bound for large delays in the project.

Packages that cannot be upgraded to support .NET Core/Standard are even more painful though. If you are lucky, there will be a similar library that you can just drop in and do some minor refactoring. This is the best case scenario, but I find it fairly uncommon unfortunately.

I hit a fairly large issue personally with the `WindowsAzure.ServiceBus` package. It supported .NET Core, but to do that, you need to basically refactor the whole initialization for the service bus in your worker service. Luckily the event and command handlers stay largely untouched in this process :relieved:

## Legacy Features

If you are using any SOAP services making use of the WSDL auto-generated service references in .NET Framework, you are going to have to do some refactoring work to get them up and running. Your two main options are finding a SOAP client for .NET Core (I personally haven't investigated this option much) or migrating to using a plain old `HttpClient` instead.

Another common part of projects that generally doesn't migrate directly to .NET Framework is the database migrations. There are many different ways of setting these up in a project, this can include:

- MSBuild based migrations
- Standalone EXE command-line migrations
- Powershell migration scripts
- Home-cooked .NET console app migrations

Some of these are difficult to migrate to .NET Core - particularly MSBuild based migrations as these are generally quite tightly coupled to `csproj` files and .NET Framework dependencies. Library maintainers are making leaps and bounds here though. If your DB migrations library is actively maintained, there is a good chance there is a .NET Core solution available. Just make sure to check what is involved to get it up and running.

## Development Environment

This is most likely not a big concern for most people, however for developers in large enterprises, it may be required to go through a lengthy process to get the .NET Core SDK software approved to be installed on developer PC's. This will pretty much stop you from starting the migration until you can run the `dotnet` CLI locally - unless you already have access to Docker or similar tools.

## CI/CD Pipeline

Another item of work as part of the migration will be upgrading any CI/CD pipelines for the project. Depending on your CI/CD landscape, this can range from being trivial to quite complicated.

From my experiences, the easiest pipelines to upgrade are automated systems like GitHub Actions, Bitbucket Pipelines and AWS CodeBuild as they are all container based systems. You upgrade your YAML file and it just pulls in a .NET Core based container with the right SDK version.

The more complicated pipelines are those which are typically located on-premise like Jenkins, Travis and TeamCity. This may involve getting approval and installing the .NET Core SDK on each build server.

## Target Environment

The final area of investigation is the target runtime environment for the application. This is sometimes overlooked and only becomes apparent when deploying the application out. You are instantly greeted with an error message when accessing the application and it isn't always clear what the cause is.

First and foremost, you want to ensure that the target environment supports .NET Core with the right version of `netcoreapp` that you are targeting in your `csproj` file. An  alternative is to use self-contained deployments, however you should consider the size impact this can have to your applications.

Secondly, you need to ensure that whatever method you use to get your environment specific configuration into your application, is compatible with .NET Core and isn't tightly coupled to .NET Framework.

---

# Pre-Migration

With the planning part now complete, you should have started to form a fairly solid timeline estimate for the migration project.

From here, if you have decided to move ahead with the migration now, you can look at the pre-migration work.

## Migrate to .NET Framework 4.7

I find this step to be quite simple in practice. Most of the time, web servers have been kept up-to-date via Windows Updates, which should include new .NET Framework versions. If not, installing the upgrade package is quick and painless.

The benefit of migrating to .NET Framework 4.7 first, is that it gives you much broader coverage of .NET API's and will unlock more NuGet package options. You can read more about [Microsoft's advice on that here](https://docs.microsoft.com/en-us/dotnet/core/porting/#overview-of-the-porting-process). 4.7.2 is the best if possible, but I've also had a good experience going for 4.7 instead.

From my experience, upgrading to 4.7 also helps to resolve spontaneous issues with `System.Net.Http` dependencies. The core of this issue is that .NET Framework includes a specific version of `System.Net.Http` and newer .NET Standard NuGet packages will target different versions of the same package, leading to conflicts. .NET Framework 4.7 gives you a more up-to-date `System.Net.Http` which helps this issue.

## Migrate to PackageRef

Another tip from Microsoft's [porting guide](https://docs.microsoft.com/en-us/dotnet/core/porting/#overview-of-the-porting-process) is to move to the `PackageRef` format for NuGet package references, instead of the `packages.config` file. This just helps the actual migration step go a little smoother as it is one less change to do later.

Visual Studio on Windows actually just includes a menu option to do this for you automatically - I would recommend that if possible. However doing it yourself also isn't that much work, and can actually be a good excuse for evaluating all of you packages in use, one-by-one.

## Upgrade all the NuGet's

Now that the NuGet packages are referenced using the `PackageRef` format, all of the packages can be upgraded to the latest versions. As a first pass, I try and get everything working with the most recent versions of packages, that don't require major refactoring. Then you can boot up the application to ensure it is still working.

At this stage, most NuGet packages are probably up to date, but some will require refactoring. You have a choice with the remaining packages - if they support .NET Standard and Core, you can leave them until after the migration, or you can go ahead and do the refactoring now.

If there isn't any available upgrades for a NuGet package, you will either have to refactor to a similar package, rewrite the NuGet code yourself, or remove the functionality all together.

## Replace Obsolete Functionality

The final step that can be done before starting the migration proper, is to remove or replace any obsolete functionality. A good example of obsolete functionality in .NET Framework is the SOAP based Service References. These were auto-generated bindings from WSDL files that generally connected to SOAP based services.

Support for Service References has been fully removed from .NET Core and they will no longer work. As discussed earlier, you can either try to get a .NET Core/Standard based SOAP client to replace these, or build a custom implementation based around HttpClient. Alternatively, if it is an option, your API provider may have a newer REST based API available for use - this is worth investigating as it may save you time if the SOAP API was going to be deprecated at some point in the future anyway.

# Conclusion

In this post, we have covered:

- Why you should migrate to .NET Core
- What is .NET 5 and why you don't need to wait until it is released to migrate
- My personal high level process for approaching the migration of large applications
- Explored the first part of the migration process, planning
- Went over what work can and should be performed prior to starting the .NET Core migration

If I have missed anything you can think of, please let me know and I'll update it. My goal is to compile a source for everything required in the migration process to assist anyone carrying out a migration in the future. 

To keep on reading, check out the [next post in the series]({{< ref "blog/migrate-dotnet-framework-to-core-part2" >}}).