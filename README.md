# fogup

Backup files from one cloud storage provider to another.

Designed to backup from Openstack Swift to AWS S3, but other providers supported
by the Ruby Fog gem may also work.

## License

Licensed under the EUPL V.1.1.

For full details, see [LICENSE.md](LICENSE.md).

## Requirements

* Ruby 2 (latest stable version recommended)
* Bundler

## Installation

* Clone this Git repo
* Run `bundle install`

## Configuration

Create a YAML config file fog.yml in the root of your cloned repo:
``` yaml
## fog.yml
## source provider
src:
  credentials:
    provider: OpenStack
    openstack_auth_url: https://swift.example.com/tokens
    openstack_username: YOUR_OPENSTACK_USERNAME@example.com
    openstack_api_key: YOUR_OPENSTACK_API_KEY
  directory: src-directory-on-swift
## destination provider
dst:
  credentials:
    provider: AWS
    aws_access_key_id: YOUR_AWS_ACCESS_KEY_ID
    aws_secret_access_key: YOUR_AWS_SECRET_ACCESS_KEY
    region: eu-central-1
  directory: dst-bucket-on-amazon
  ## optional prefix can be given to backup files to a sub-directory
  ## of the destination provider
  # prefix: backups/
```

## Usage

`bundle exec fogup`
