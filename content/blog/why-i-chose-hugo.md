---
title: "Why I chose Hugo"
description: "I explain why I chose Hugo when rebuilding my site over other alternatives like SPAs or server-side tech"
date: 2019-05-09
tags: ["hugo"]
---

Just the other day, I decided to rebuild my personal website. This post covers my decision around using Hugo to build out the sites content.

# Why not Wordpress?

When rebuilding this site, one of my goals was to try and avoid any server-side hosting. There were a few reasons behind doing this:

* My site is static content, it doesn't change apart from when publishing new content - I didn't even need a contact form

* I didn't want to pay monthly fees :money_with_wings: for server rental - my site doesn't get high traffic so the CPU/memory utilisation of any server is low so it's a bit of a waste

* Running server-side code means you have a server which needs to be kept up to date with patches - maintenance hassle

* I've never really committed to building a fully static site, so I wanted to see how far I could take it with plain ol' HTML

So I set out to start planning how the site would come together.

This article covers the reasons why I chose Hugo over alternatives and then goes through my process to build a site. If you would like to also read about getting the Hugo site deployed using S3 and CloudFront, [read my next article]({{< ref "hugo-with-s3-cloudfront.md" >}}).

# To SPA, or not to SPA?

At first I considered hand-coding HTML documents, but decided against this as I didn't want to be copying the same `<head>`, `<meta>`, `<script>` elements into every file - this would cause a massive maintenance headache in the future if I ever changed the styling or layout.

This brought me to using a template engine of some sort. There are two big options in this space that I found:

* SPA (single page application) frameworks such as Angular, Vue and React - two of which I am very familiar with - using them on projects many times.

* Static Site Generators - something I have never played around with before, but look very promising for this application - as a bonus, you can also write content using Markdown :+1:

I decided against using a SPA framework as my site is all static content - so no need for Javascript to render all of the content - and I also couldn't lean on SSR (server-side rendering) offered by the SPA frameworks due to not having a server :smile:

# Static Site Generators

This left me with Static Site Generators as the other main contender. I researched which ones are popular and how they would fit my use case. The decision came down to Jekyll and Hugo. Both are very popular in this space so it was a little hard to choose between them.

I ended up choosing Hugo as it doesn't require you to have Ruby :gem: installed - something I don't personally use in any other projects. It also helped that Hugo is a CLI executable that is installable from most OS's package managers.

# Getting Started with Hugo

Now that I had decided on Hugo, the next step was to create the site. This was simple enough, the people working on the Hugo docs have done a great job at making it quick and easy to get started. I opened up the [Quick Start](https://gohugo.io/getting-started/quick-start/) page and followed along - first step is to install Hugo. On OSX this is simple.

```bash
brew install hugo
```

The next step is to actually create your basic site structure.

```bash
hugo new site jaydenm-com-site
```

To serve up the site.

```bash
hugo serve -D
```

Weirdly enough, if you serve up the site at this point, you will only get a blank page - no 404 or 500 errors or anything like that. I quickly found out (serves me right for being impatient :man_facepalming:) to get content to display, you need a theme.

# The Hardest Part - Picking a Theme!

There is a massive number of themes available online at the [Hugo Themes](https://themes.gohugo.io/) site. It took me a long time to actually find some themes that I liked (don't get me wrong, most are great, just not what I was looking for). Once I found a few, I decided that none were exactly what I wanted for my site - plus I wanted my site to have a bit of personal flair :dancer: and be different to every other site out there.

I decided to build my own theme - which is actually very easy to do.

# Building a Theme

Seeing as all themes need the source code public to be listed on the Hugo directory, you can easily dig into any themes you like and see exactly how they are doing something. This fact, coupled with the [Hugo Theme documentation](https://gohugo.io/themes/creating/) made it quite easy to build something out - exactly how I liked it.

The Hugo CLI also has a command to scaffold out a new theme.

```bash
hugo new theme jaydenm
```

You can see the files for the theme that I built in my [Github repo here](https://github.com/drjaydenm/jaydenm-com-site/tree/master/themes/jaydenm).

# Adding Content to the Site

Now that I had a theme, I could start adding content to my site. That is made super easy with the Hugo CLI.

```bash
hugo new blog/why-i-chose-hugo.md
```

Hugo also has archetypes which serve as default templates for new content. Here is an example of the archetype I use for a new blog post.

```markdown
---
title: "{{ replace .Name "-" " " | title }}"
description: "{{ replace .Name "-" " " | title }}"
date: {{ now.Format "2006-01-02" }}
tags: []
draft: true
---

**Insert content here**
```

# Marking Content as Published

Once I had a piece of content that was ready to be marked as published (allowed to appear on the site), I found you can simply remove the `draft: true` parameter in the content file.

You can then preview what the published version of the site looks like at any time by removing the `-D` flag from the `hugo serve -D` command. Aka.

```bash
hugo serve
```

# Publishing the Site

Once I was happy with the site as a whole, I was ready to publish the site and make it available to the Internet. With a Static Site Generator, this is usually when you will want to compile everything to raw HTML. This is easy with Hugo, just run

```bash
hugo
```

Hugo will output all of the site content as HTML to the `public` directory which can then be place somewhere to host it.

# What Now?

I made the choice to use S3 Web Hosting functionality to host the site. This was mainly due to me already having an AWS account setup and being familiar with S3 and the rest of the AWS ecosystem. This is covered in my next post if you would like to [read about that]({{< ref "hugo-with-s3-cloudfront.md" >}}).

If you want to see the code that I ended up with, you can take a look on [Github here](https://github.com/drjaydenm/jaydenm-com-site).

If you have any questions or suggestions, I would love to hear from you.