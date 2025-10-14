<h1>
  <a href="https://www.drupalforge.org/">
    <img src="drupalforge.svg" alt="Drupal Forge" height="100px" />
  </a>
  <br />
  <br />
  Starter Template
</h1>

This repository is a template for creating a Drupal Forge app from a Composer
project. It performs a clean Drupal install with a default admin password of
_admin_. __If you want to turn an existing Drupal Forge app into a template,
you do not need this.__ The Composer project to create is specified by the
`PROJECT` environment variable. If `PROJECT` is not defined, it defaults to
[drupal/recommended-project](https://www.drupal.org/docs/develop/using-composer/starting-a-site-using-drupal-composer-project-templates#s-drupalrecommended-project).
- You can set a different default value for `PROJECT` in
  [.devpanel/composer_setup.sh](.devpanel/composer_setup.sh#L10).
- To skip creating a project with Composer, add your own `composer.json` to the
  repository root.


## How to run this template

- This repository is optimized for fast deployment with
  [DevPanel](https://www.devpanel.com). DevPanel deployment files are in the
  [`.devpanel`](.devpanel) directory. You can add the `.devpanel` directory
  from this repository to an existing repository.
- You can run this repository with any tool that supports
  [dev containers](https://containers.dev/supporting).
- This repository is also configured to run with [DDEV](https://ddev.com).


## Publishing a quick start image

For faster deployment, go to the [Actions](../../actions) tab in GitHub after
you create a new repository from this template and add a workflow that
pre-deploys your template in a Docker image, reducing the time needed to launch
a site.
- If your repository is in the Drupal Forge
  [GitHub organization](https://github.com/drupalforge), the Drupal Forge
  _Docker build and push template_ can set up the workflow for you. The
  workflow will generate a new Docker image whenever a commit is pushed to the
  `main` or `test/*` branches. Your images will be in the Drupal Forge
  [Docker Hub account](https://hub.docker.com/u/drupalforge).
- Otherwise, set up your own workflow with the
  _[Drupal Forge Docker Publish](https://github.com/marketplace/actions/drupal-forge-docker-publish)_
  action. It includes a reusable workflow you can call from your workflow. This
  is how the reusable workflow is used in the Drupal Forge _Docker build and
  push template_:

  ```yaml
  name: Docker build and push template
  on:
    push:
      branches:
        - main
        - test/*
    workflow_dispatch:
  jobs:
    build-application:
      uses: drupalforge/docker_publish_action/.github/workflows/docker-publish.yml@main
      with:
        dockerhub_username: ${{ vars.DOCKERHUB_USERNAME }}
      secrets:
        dockerhub_token: ${{ secrets.DOCKERHUB_TOKEN }}
        dp_ai_virtual_key: ${{ secrets.DP_AI_VIRTUAL_KEY }}
  ```
