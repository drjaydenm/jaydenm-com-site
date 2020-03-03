---
title: "Hosting Hugo with S3 and CloudFront"
description: "If you use S3 and CloudFront to publish your Hugo site, here are some tips and tricks to help you out"
date: 2019-05-12
tags: ["hugo", "s3", "cloudfront"]
header_image: "header.jpg"
---

I recently decided to rebuild my personal website. I made the decision to use Hugo to build out the sites content. For more background on why I chose Hugo, you can [read my previous post]({{< ref "blog/why-i-chose-hugo" >}}).

I also made the decision to avoid using any server-side hosting. For all of the details around this decision, again, you could [check out my previous post]({{< ref "blog/why-i-chose-hugo" >}}) :smirk:. But the tl;dr of those reasons is:

* This site is static - it only changes when I post/update content

* It is cheaper to host a site if you can avoid running servers

* Servers have to be maintained with patches

* A static site would be a new challenge to build

# Why use S3?

There are many options for hosting your website without running your own servers. The most common option seems to be paying a web-host to manage the server and provide you a means of dumping the site content on there. Then they will just use Apache or Nginx to serve it up to the web.

I have wondered for a while why you can't use S3 or other cloud storage platforms to host static sites, but only recently found out that S3 actually has a feature for this exact purpose! :boom:

I decided on using S3 over alternatives as I am most familiar with S3 and already have an AWS account.

# So where does CloudFront come in?

I went ahead and setup S3 with its [Web Hosting feature](https://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html). This worked pretty well, however it didn't support HTTPS **at all** without using the S3 branded domain. :expressionless: :sigh:

After looking around quite a bit, the next best solution was to use CloudFront in lieu of S3 Web Hosting. The general idea is to store your content in S3 and access it via CloudFront.

I'm not going to cover how this part was setup as there are [plenty](https://lustforge.com/2016/02/27/hosting-hugo-on-aws/) of [tutorials](https://habd.as/post/zero-to-http-2-aws-hugo/) out [there](https://nickolaskraus.org/articles/hosting-a-website-with-hugo-and-aws/) for this.

# But I still wasn't happy...

CloudFront made things a lot better - I got the HTTPS support I was looking for, plus HTTP/2 support - and the site loaded a whole lot faster being on a CDN too. :+1:

The problem was, CloudFront doesn't support rewriting `/` to `/index.html` on any other path than the base domain URL. (really?! :disappointed:) This actually wasn't an issue until I disabled the S3 Web Hosting feature (I disabled this so that my S3 bucket could be private - I wanted all traffic to come through CloudFront). The reason for this was that S3 Web Hosting was rewriting all CloudFront requests for `/` to `/index.html` behind the scenes... sneaky. :thinking:

 None of the articles I linked earlier on setting up Hugo with S3 and CloudFront have a solution for this either. I looked around to see if any other Hugo users had found a solution, but everyone was recommending to use the S3 Web Hosting feature.

# Lambda to the rescue!

 Luckily, I happened upon an article from AWS about [using Lambda@Edge to implement the default directory index files using CloudFront](https://aws.amazon.com/blogs/compute/implementing-default-directory-indexes-in-amazon-s3-backed-amazon-cloudfront-origins-using-lambdaedge/). After researching Lambda@Edge and checking the pricing, I decided it should do what I'm looking for.

The solution was actually quite nice. Basically, for every request that came in to CloudFront, it would run this Lambda to work out which file from S3 it needed. As a bonus, CloudFront will cache these responses too - so the Lambda only gets called once for each path (great idea Amazon!).

The only catch with this is that all Lambda's need to be authored in the North Virginia (us-east-1) region - not a biggie for me.

# Let there be rewriting

After a few small tweaks to Amazon's version, I got it working how I liked.

```javascript
'use strict';
exports.handler = (event, context, callback) => {
    // Extract the request from the CloudFront event that is sent to Lambda@Edge 
    var request = event.Records[0].cf.request;
    
    // Extract the URI from the request
    var olduri = request.uri;

    // Match any '/' that occurs at the end of a URI. Replace it with a default index
    var newuri = olduri.replace(/\/$/, '\/index.html');
    
    // Log the URI as received by CloudFront and the new URI to be used to fetch from origin
    console.log("Old URI: " + olduri);
    console.log("New URI: " + newuri);
    
    // Replace the received URI with the URI that includes the index page
    request.uri = newuri;
    
    // Return to CloudFront
    return callback(null, request);
};
```

I am actually quite happy with the Lambda code - very short and to the point. If you take out all the comments and logging, it ends up at 6 lines of code - quite impressive (5 lines excluding the export - you could make it even shorter by removing temporary variables).

After adding this Lambda to the CloudFront distribution, the `index.html` rewriting was working perfectly.

# Could this also fix another problem?

Everything was now working just as I had initially hoped it would. The only minor problem I had left was handling redirects from my other domains. I have 3 personal domains; [jaydenm.com](https://jaydenm.com/), [jaydenmeyer.com](https://jaydenmeyer.com/) and [drjaydenm.com](https://drjaydenm.com/). I wanted all of these to point to `jaydenm.com`.

Could a Lambda also fix this? Turns out that a Lambda was a super easy solution for this problem too.

```javascript
'use strict';
exports.handler = (event, context, callback) => {
    // Extract the request from the CloudFront event that is sent to Lambda@Edge 
    var request = event.Records[0].cf.request;

    // Get the host from the request headers if present
    var host = "jaydenm.com";
    if (request.headers && request.headers.host && request.headers.host.length) {
        host = request.headers.host[0].value;
    }
    
    // Redirect to the correct domain if required
    if (host != "jaydenm.com") {
        console.log(`Redirecting from ${host} to jaydenm.com`)
        
        // Do a redirect to the correct domain
        const response = {
            status: '301',
            statusDescription: 'Moved Permanently',
            headers: {
                location: [{
                    key: 'Location',
                    value: 'https://jaydenm.com' + request.uri,
                }],
            },
        };
        callback(null, response);
        return;
    }
    
    callback(null, request);
};
```

This one clocks in at 16 lines of code, but a big chunk of that is the object initializer for the response.

# Conclusion

Overall, I am quite happy where this ended up. I got some experience using Lambda@Edge and now have knowledge of where it can be used and what it is good for. (I was interested by the idea of having a site served purely through Lambda@Edge :thinking:).

It is a little annoying that the S3 Web Hosting feature doesn't support HTTPS, but there are apparently [loads of features coming soon](https://aws.amazon.com/blogs/aws/amazon-s3-path-deprecation-plan-the-rest-of-the-story/) - maybe some of those will boost the usefulness of the Web Hosting functionality.

As always, if you have any questions or suggestions, I would love to hear from you. Also, if you are interested in why I chose Hugo for my site, [check out my previous post]({{< ref "blog/why-i-chose-hugo" >}}).