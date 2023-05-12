---
title: "Integrating Partytown in a Hugo site"
description: "This post covers how to setup Partytown in a Hugo site to offload JavaScript to a web worker and boost your site performance"
date: 2023-05-12
tags: ["hugo", "performance"]
header_image: "header.jpg"
---

In this post I'm going to cover the process I went through to integrate the Partytown library into my Hugo static website.

# So what is Partytown?

For anyone who hasn't heard of Partytown, it's a [library by the team at builder.io](https://partytown.builder.io/) that moves script processing off the main thread and into a web worker. This is ideal for any third-party asynchronous code that runs on a typical website like analytics, metrics, A/B testing or advertising.

These libraries generally initialise themselves as your website loads, even when they are marked as `async` and `defer` on the `<script>` tag. This increases your websites total blocking time on load, which is used as a metric by search engines for the quality and performance of your site. You can usually see the impact of this in your sites Lighthouse reports. If you haven't run a report on your site recently, [you can do so here](https://pagespeed.web.dev/). I ran a report over this website as a bit of a loose benchmark before implementing Partytown.

{{< figure src="lighthouse-before.png" caption="Lighthouse report before implementing Partytown" >}}

The total blocking time is quite large in the report above because I added a script that causes a noticeable slowdown. This will help make the overall improvement much more apparent in the reporting when we're done as the scripting on this site is quite light.

# How to integrate Partytown in Hugo

Integrating Partytown into a Hugo site is fairly straight forward overall, but there are a couple of moving parts to handle due to the way Hugo handles assets. I looked around myself on the web when I was doing it and couldn't find any information or other people who have done the same. So I thought it would be a good opportunity to document the process I followed for others to find.

There are a few steps to follow when integrating Partytown into a static HTML website [which you can see here](https://partytown.builder.io/html). To sum them up, we'll need to do the following:

- Install the `@builder.io/partytown` NPM package
- Setup mounts for the Partytown assets
- Include the `partytown.js` file in the `<head>` section of our site
- Declare the Partytown config object in the `<head>`
- Mark scripts to be ran with Partytown

Before you can install an NPM package in your Hugo site, you need to ensure you have a `package.hugo.json` file. This file allows Hugo to track NPM dependencies across your project, themes and modules. If this file doesn't already exist in your project root, create it.

```json
{
  "name": "my-site-name",
  "version": "0.1.0",
  "devDependencies": {
    "@builder.io/partytown": "^0.8.0"
  }
}
```

After adding Partytown to that file, you need to get Hugo to update the actual `package.json` file with the dependencies in the `*.hugo.json` files.

```bash
hugo mod npm pack
```

Now you can run a normal NPM install.

```bash
npm install
```

Now the package is installed, we can move onto adding it into the `<head>` section. To do this, we'll need to mount the `partytown.js` file from the `node_modules` into a directory inside the project. Hugo isn't able to reference a file inside the `node_modules` directory without hard pointing to that directory in the template which is bad practice.

To setup a mount, you need to open up the `config.toml` file in the root and add the following.

```toml
[module]
[[module.mounts]]
  source = 'assets'
  target = 'assets'
[[module.mounts]]
  source = 'node_modules/@builder.io/partytown/lib/partytown.js'
  target = 'assets/js/partytown.js'
[[module.mounts]]
  source = 'static'
  target = 'static'
[[module.mounts]]
  source = 'node_modules/@builder.io/partytown/lib'
  target = 'static/~partytown'
  excludeFiles = 'debug'
```

This kind of looks like the parts which map `assets` and `static` to themselves aren't required, however once you declare a mount for a target, it resets the defaults, so we need to include them again manually. The end result of this config is that the `partytown.js` file will get mapped into the `assets/js` directory, and the `lib` directory will get published as `~partytown` in the published site.

Now that we have a mount for the `partytown.js` file, we can include it in the `<head>` of our template. Partytown recommends embedding the Javascript directly into the HTML rather than loading it via a URL for performance. The library is quite lightweight and only adds around 2KB to the page weight. Add the following to your `<head>`.

```html
<!-- Partytown Setup -->
<script type="text/javascript">
  partytown = {
    forward: ['dataLayer.push']
  };
</script>
<script type="text/javascript">
  {{ $partytownJs := resources.Get "js/partytown.js" | js.Build | minify }}
  {{- $partytownJs.Content | safeJS }}
</script>
<!-- End Partytown -->
```

This pulls in the mounted `partytown.js` file, builds it using ESBuild, minifies it and then embeds the contents inside a `<script>` tag in the `<head>`. We've also declared the `partytown` config variable and added a forward to `dataLayer.push`. This is because I'm using GTM (Google Tag Manager) which uses that function. Adding a forwarded function to the config means that any scripts on the main thread that call that function, will get forwarded to the web worker to execute which is very important as that is where GTM will be running from now on.

Now all that is left is to specify which scripts should be executed using Partytown instead of on the main thread. This is easily done by adding a `type` attribute to any `<script>` tags and setting it to `text/partytown`. If the script tag already has a `type` set to `text/javascript` you can just change it.

In this example, I'm wanting to move my GTM tag to be executed in Partytown, so this is what that would look like - the important part being the `text/partytown`.

```html
<script type="text/partytown">
  (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
  // ... more GTM code
  })(window,document,'script','dataLayer','{{ .Site.Params.gtmID }}');
</script>
```

And now if you reload your site, any scripts marked with the `text/partytown` type will be ran inside the web worker. You will need to double check that everything is working as expected as there are some scenarios which aren't supported, or aren't performant. Any library that uses heavy DOM scanning or manipulation is likely a bad choice as everything must be proxied through from the worker to the main thread. You'll need to check what the performance is like for your specific workload. The great thing is, you can easily move scripts in and out by changing their type. [Read more about the trade-offs here](https://partytown.builder.io/trade-offs#throttled-dom-operations).

Depending on what scripts you are looking at moving into Partytown, you may also need to configure CORS headers on your site. I'll leave this as an exercise for the reader as this can vary significantly based on your hosting provider and setup. The [Partytown documentation](https://partytown.builder.io/proxying-requests) does have some useful guidance on this.

# Summary

Now that we've integrated Partytown in our Hugo site, lets check what the performance gains in Lighthouse were compared to at the start. The result below was still running the same intensive script as before. You can see how the total blocking time metric has gone down to 70ms, even with the script running in the background as the site loads.

{{< figure src="lighthouse-after.png" caption="Lighthouse report after implementing Partytown" >}}

Hopefully this post has given you all the info you need to integrate Partytown into your Hugo site. I'm always looking for feedback, so if you have any thoughts on how to improve, please let me know.
