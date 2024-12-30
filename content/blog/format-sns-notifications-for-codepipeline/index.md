---
title: "Format AWS SNS notifications for CodePipeline with pretty text"
description: "Here we look at a method for formatting the SNS notification body as pretty text using EventBridge and no Lambda's with Terraform included."
date: 2024-12-30
tags: ["aws", "sns", "eventbridge", "codepipeline", "terraform"]
header_image: "header.jpg"
---

Recently I was setting up some new CodePipeline's and was wanting to get notification emails when they started and stopped. So I went ahead and used the standard CodePipeline notifications documented [here](https://docs.aws.amazon.com/codepipeline/latest/userguide/notification-rule-create.html). Once setting them up, I was very happy to see a massive blob of JSON coming through to my inbox - how helpful 🤦.

I then started on the quest of getting "pretty" or formatted notification emails coming through to my inbox with the information that I wanted to see. I found a few posts along the way talking about using EventBridge and Lambdas to transform the email - but this all seemed like too much effort to go to. Surely there is an easier way.

That is when EventBridge Input Transformers entered the chat! This fancy piece of functionality allows you to take an input event, and transform it on the way out to a target.

So the general idea is that AWS CodePipeline emits an event, we setup a rule for it in AWS EventBridge and on the target to SNS, we apply a transformation that takes the JSON and outputs a string. I'm going to be using Terraform to piece this all together now.

This article is assuming you're targeting AWS CodePipeline, however the Input Transformer functionality shown below will work for any EventBridge event.

# Putting it together

The first step is to setup an AWS SNS topic if you haven't already. We also need to attach an IAM policy that allows access for AWS EventBridge to publish to SNS via the `Service` of `events.amazonaws.com`.

```terraform
resource "aws_sns_topic" "pipeline_notifications" {
  name = "aws-codepipeline-ExecutionChanges"
}

data "aws_iam_policy_document" "pipeline_notifications_access" {
  statement {
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.pipeline_notifications.arn]
  }
}

resource "aws_sns_topic_policy" "pipeline_notifications" {
  arn    = aws_sns_topic.pipeline_notifications.arn
  policy = data.aws_iam_policy_document.pipeline_notifications_access.json
}
```

Make sure to subscribe to the SNS topic above after creating it so you can receive the events.

Next up, we need to create the AWS EventBridge rule that will capture the event from AWS CodePipeline. In this case, I wanted to observe the `STARTED`, `SUCCEEDED`, `FAILED` and `CANCELED` states, but there are others available [here](https://docs.aws.amazon.com/dtconsole/latest/userguide/concepts.html#events-ref-pipeline) if you are interested.

```terraform
resource "aws_cloudwatch_event_rule" "pipeline_notifications" {
  name           = "aws-codepipeline-ExecutionChanges"
  description    = "This rule routes events from CodePipeline to an SNS topic and transforms them from JSON to be readable"

  event_pattern = jsonencode({
    detail = {
      state = ["STARTED", "SUCCEEDED", "FAILED", "CANCELED"]
    }
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    source      = ["aws.codepipeline"]
  })
}
```

Now we have the event rule setup, we can finally add a target that will send the event to AWS SNS. The key part here is the Input Transformer.

This extracts the given fields at the specified paths from the incoming JSON and stores them in our own named fields. We then use those same named fields in the input template.

```terraform
resource "aws_cloudwatch_event_target" "pipeline_notifications_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_notifications.name
  arn       = aws_sns_topic.pipeline_notifications.arn

  input_transformer {
    input_paths = {
      region    = "$.region"
      execution = "$.detail.execution-id"
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
    }

    input_template = "\"The '<pipeline>' pipeline has changed to <state> state with execution ID <execution>. For more information, go to: https://<region>.console.aws.amazon.com/codesuite/codepipeline/pipelines/<pipeline>/view?region=<region> \""
  }
}
```

Here is an example of what the email body will look like when we finally receive it.

`The 'my-pipeline' pipeline has changed to STARTED state with execution ID 1234-5678. For more information, go to: https://us-east-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/my-pipeline/view?region=us-east-1 `

A few things I found out the hard way:

- The input template must contain double quotes at the start/end
- Having a space at the end is required for the URL to work, otherwise most email clients will add the double-quote to the URL.
- The input template must have all characters escaped (no newlines or double quotes unless they are escaped).
- Newline characters do not work - if you put `\n` in the template, it will output `\n` verbatim as the message is purely text.

If you trigger a pipeline execution, or whatever else causes your chosen event to be emitted, you should now get a pretty formatted email (or whatever other SNS subscription type you used).

I hope you found this post useful, and as always, if you have any thoughts on how to improve, please let me know.
