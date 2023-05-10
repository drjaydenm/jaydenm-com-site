---
title: "Migrating .NET Framework Applications to .NET Core (Part 2)"
description: "The second post in my series on migrating from .NET Framework to .NET Core. I cover everything from upgrading packages, right through to using the modern features"
date: 2020-03-08
tags: ["dotnet", "csharp"]
header_image: "header.jpg"
---

# What was covered last time?

In [the last post]({{< ref "blog/migrate-dotnet-framework-to-core-part1" >}}), I covered:

- Why you should migrate to .NET Core
- What is .NET 5 and why you don't need to wait until it is released to migrate
- My personal high level process for approaching the migration of large applications
- Explored the first two parts of the migration process, planning and pre-migration
- Went over what work can and should be performed prior to starting the .NET Core migration

This post will follow on from there, and assumes that you have read the previous post.

# Pre-requisites

Before diving into the actual migration, it is good to take note of where you are at. The following should all be completed prior to starting:

- All NuGet packages up to date, or at least .NET Standard compatible
- NuGet packages migrated to the `PackageReference` format
- All projects in the solution should be targeting .NET Framework 4.7 or higher
- No remaining service references in use
- No projects should reference more than one executable project (API, worker, command line, forms app, etc) as it makes upgrading projects one-by-one impossible or very difficult - check [the previous post]({{< ref "blog/migrate-dotnet-framework-to-core-part1" >}}) for more details on why

# Migration

If you can check off all of the above, you have pretty much done as much as you can to make the actual migration go as smoothly as possible.

To keep the project timeline as short as possible, I find a good mindset whilst doing the migration to be "is this task required to get an MVP working on .NET Core". Following this at every step will enable you to distinguish tasks that must be done, versus those that are nice to have and can be done later.

With that in mind, it is worth noting that quite a lot can be completed after having a working migrated .NET Core application. A good example of this is the configuration, some may believe it is required to move to `appsettings.json` for .NET Core, however Microsoft provides a plugin package that adds out of the box support for the trusty old `ConfigurationManager` and `web.config` or `app.config`.

## Upgrade shared libraries

The first piece of the migration process is to move any shared libraries to .NET Standard. I've listed this as part of the actual migration, and not part of the pre-migration as it can break your build pipeline and potentially even your application when it deploys. This can be due to build server compatibility issues, or even dependency binding and versioning issues if all 3rd party packages aren't configured correctly.

Upgrading a project to .NET Standard is as simple as replacing your `.csproj` file with an SDK style one similar to the below.

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <!-- This is required in every SDK style project file -->
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>

  <!-- These are your NuGet packages -->
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="12.0.3" />
    <PackageReference Include="Serilog" Version="2.9.0" />
  </ItemGroup>

  <!-- This is a reference to another project -->
  <ItemGroup>
    <ProjectReference Include="..\App.OtherSharedLib\App.OtherSharedLib.csproj" />
  </ItemGroup>

</Project>

```

These newer SDK style project files are a lot simpler to read than the older .NET Framework files and are meant to be easily editable by hand. Sometimes IDEs like Visual Studio can add erroneous or redundant entries into the `csproj` file so it is good to keep an eye on it to keep it clean.

## Upgrade application projects

Now that all the shared projects are targeting .NET Standard, the actual application projects can be upgraded to target .NET Core. Updating the `csproj` file is very similar to the shared project process above, except for these two lines

```xml
<OutputType>Library</OutputType>
<TargetFramework>netstandard2.0</TargetFramework>
```

will most likely be changed to something like

```xml
<OutputType>Exe</OutputType>
<TargetFramework>netcoreapp3.1</TargetFramework>
```

The exact variation will depend on what type of application you are migrating as the `OutputType` element has various values it can be set to. The best bet is to read up the documentation for your specific type of application. If your application is an ASP.NET application, you can even omit the `OutputType` completely.

Once you have updated the `csproj` of the application, you will generally need to update the testing project to .NET Core too, unless it is a library project type targeting .NET Standard.

I find it is best to migrate one application at a time so that you minimise the errors when you do a compilation (there can be a load of errors for large applications), and it also allows you to boot up the whole solution to test it still works along the way.

## Changes from ASP.NET to ASP.NET Core

When migrating API or MVC applications to .NET Core, I have come across a few gotchas that don't immediately cause issues and are only found after regression testing, or even worse, after going to production. Some of these are also easy to glimpse over, even if you do a full on manual regression test.

### Model binding changes

The first of these is the way that model binding works in .NET Core. It is close enough in behavior and syntax, that it looks to work straight out of the box in most scenarios, however this can be misleading. Take this controller below as an example

```csharp
public class Item
{
    public int ItemId { get; set; }
    public string Name { get; set; }
}

[Route("api/v1")]
public class ItemsController : ControllerBase
{
    [HttpGet("items/{itemId}")]
    public IActionResult UpdateItem(int itemId, Item item)
    {
        return Ok();
    }
}
```

When we tested this in .NET Framework, it bound the `itemId` route parameter to both the `itemId` method parameter, and the `ItemId` property on the model. However when migrating over to .NET Core, the model seemed to take priority and the method parameter was ignored.

This could be fixed in two ways, add the `[FromQuery]` attribute to the `itemId` parameter, or remove the parameter completely and only use the model `ItemId` property.

### Authentication changes

As part of the migration, you will likely have to refactor parts of your authentication logic. How much you have to refactor is dependant on how much out-of-the-box logic you were using in .NET Framework. Around the time of the OWIN pipeline, a whole lot of baked in authentication logic was added for OAuth2 and other providers. If you are using this, then I find it is mostly reusable straight away, you just need to hookup using the new method in `Startup.cs`.

This is what you would write in .NET Framework

```csharp
app.UseJwtBearerAuthentication(new JwtBearerAuthenticationOptions
{
    AllowedAudiences = new[] { "https://myapi.com/" },
    IssuerSecurityTokenProviders = new IIssuerSecurityTokenProvider[]
    {
        new SymmetricKeyIssuerSecurityTokenProvider("https://authidp.com/", "supersecret123")
    }
});
```

and now becomes this in .NET Core

```csharp
app.UseJwtBearerAuthentication(new JwtBearerOptions
{
    Audience = "https://myapi.com/", 
    AutomaticAuthenticate = true,
    Authority = "https://authidp.com/",
    IssuerSigningKey = new X509SecurityKey("supersecret123")
});
```

If you are using a more advanced authentication procedure, such as using scopes in JWT's to authorize various API endpoints, it may be a little more complicated as quite a lot of the APIs behind the scenes have changed.

---

# Modernisation

When you are looking to start modernisation, your application should be fully up and running on .NET Core. If not, don't start performing parts of the modernisation yet, unless your migration is already far ahead of schedule.

## Migrating to IConfiguration

Depending on how many configuration entries you have, this task can range from quick to quite lengthy.

It also depends on the support of your CI/CD pipeline for JSON file substitution. If you don't have any secret values and are happy to have all configuration for every environment in the config file, you could actually get away with simply using the `appsettings.ENV.json` environment override files. If not, you will need CI/CD support - most providers these days have JSON support out of the box.

To start migrating, simply install the `Microsoft.Extensions.Configuration.Json` package. After this, you need to hookup the configuration in your `Program.cs`.

```csharp
var configBuilder = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile("appsettings.{Environment}.json", true, true)
    .AddEnvironmentVariables();
var config = configBuilder.Build();
```

> Note that the `AddEnvironmentVariables()` call requires the `Microsoft.Extensions.Configuration.EnvironmentVariables` package to be installed.
>
> One of the nicest things about the `IConfiguration` provider is that you can chain these different providers together, and they override each other in order with the last one taking priority.

Now create a file named `appsettings.json` in the project root alongside your `web.config` or `app.config`. All configuration in the `appsettings.json` file is relative to the root, unlike `web.config` where everything is under the `<appSettings>` node.

```json
{
  "SomeConfigKey": "Value123",
  "NestedObject": {
    "NestedValue": "abc"
  },
  "ArrayOfThings": [
    {
      "Value": 1
    },
    {
      "Value": 2
    }
  ]
}
```

## Migrating to Microsoft.Extensions.DependencyInjection

With the introduction of the `Microsoft.Extensions.DependencyInjection` package, there are far fewer reasons today to use another IoC container. Unless you really need some feature that isn't provided by the Microsoft package, you are most likely better off using it.

To get started, simply install the `Microsoft.Extensions.DependencyInjection` package, or if you are building an ASP.NET application, this package will be included by default by referencing `Microsoft.AspNetCore.All`. From here, you need to hook it up to your `IHostBuilder` implementation which relies on having an IoC configuration class, usually implemented as a `Startup.cs` file.

This is a minimal implementation of `WebHostBuilder` referencing a `Startup.cs` file.

```csharp
public class Program
{
    public static void Main(string[] args)
    {
        var host = new WebHostBuilder()
            .UseStartup<Startup>()
            .Build();

        host.Run();
    }
}
```

This is an example of a `Startup.cs` file that could go along with it.

```csharp
public class Startup
{       
    public void ConfigureServices(IServiceCollection services)
    {
        services.AddControllers();

        // Add a custom service to the IoC container
        services.AddTransient<ISomeService, SomeService>();
    }

    public void Configure(IApplicationBuilder app)
    {
        // Hook up the API controllers
        app.UseRouting();
        app.UseEndpoints(endpoints =>
        {
            endpoints.MapControllers();
        });
    }
}
```

These are just two of many aspects that you could modernise once moving to .NET Core.

# Wrapping up

In this post, we covered:

- Upgrading shared libraries to .NET Standard
- Upgrading application projects to .NET Core
- Some of the changes in functionality or APIs that you should expect as part of upgrading the application project
- Migrating to the Microsoft IConfiguration provider
- Migrating to the Microsoft Dependency Injection provider

So that brings part 2 of the series to an end, if you missed part 1, [check it out here]({{< ref "blog/migrate-dotnet-framework-to-core-part1" >}}). If I've missed anything, let me know :smile:.
