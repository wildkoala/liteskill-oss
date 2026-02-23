# Hello World Tutorial

Welcome! This tutorial gets you up and going with LiteSkill.

## Docker Compose

The fastest way to get up and running is with Docker Compose. Ensure it's installed on your system and then run the following script:

```bash
git clone https://github.com/your-org/liteskill-oss.git && cd liteskill-oss
docker compose up
```

## Admin Setup

Open a new browser window on the other half of yours and navigate to [http://localhost:4000/](http://localhost:4000/). 

1. Set the admin password.
1. Skip connecting your data sources for now.
1. Login using ```admin``` in place of an email address and the password you just set.

## Configuring an LLM Provider

Before you can chat, you'll need to configure at least one LLM provider. For testing purposes, we'll use [OpenRouter](https://openrouter.ai/).

### Get your OpenRouter Information
1. Open a blank text file, we'll be saving some data in here.
1. In a new browser tab, go to [OpenRouter's website](https://openrouter.ai/).
1. Sign Up or log in.
1. Click "Get API Key".
    - Create a key and save it into your file.
1. Then search for "Haiku" and use the first model that pops up. We're going to copy more info into our text file
    - the model id.
    - the model input token cost per million(M).
    - the model output token cost per million(M).

### Add the OpenRouter Provider
1. In the LiteSkill app, navigate to ```Admin > Providers``` and click the purple "Add Provider" icon in the top right.
1. Configure the Provider:
    - Name: "OpenRouter Provider"
    - Click on the Provider Type drop down and select: "openrouter"
    - API key: Paste in the API key you saved in the text file
    - You don't need to put anything in the Provider Config section
    - Set the flag for Instance-wide (it's just you for now!)
    - Click Save

### Add a Model
1. Now click on the ```Models``` tab, next to the ```Providers``` tab in the navbar.
1. Configure the Model:
    - Display Name: "Haiku"
    - Provider: "OpenRouter Provider" (should be set automatically)
    - Paste in the model ID you saved in the text file.
    - Model Type: "inference" (should be set automatically)
    - Input Cost and Output Cost you saved in the text file
    - Leave the model configuration blank for now.
    - Click Save

Chat should now work!! Click the "+" icon next to "Conversations" in the top left and type "Hello world!"
