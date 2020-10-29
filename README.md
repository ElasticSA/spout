# Elastic EC_Spout demo scripts

Script for the Elastic Stack demonstrations; but can also be used on their own. 

## Getting Started

Look at the follow scripts as they are not tied to any specific demo environment and be used anywhere:
 - agent_install_enroll.ps1|sh
 - beats_install.ps1|sh
 - beats_configure.ps1|sh
 - utilities.ps1|sh
 
The ps1 scripts are powershell scripts for Windows and the sh scripts are shell scripts for Linux.

The scripts read a config file called "elastic_stack.config", see the example file.

The remaining scripts are specific to the skytap demo environment.

### Prerequisites

None, the scripts are standalone

### Installing

Copy the scripts to a target system and use as needed.

## Deployment

These scripts are for demonstration purposes only, they do not follow all production deployment
recommendations. Most notably they use the 'elastic' superuser and not a dedicated beats user.

## Contributing

Get in touch with me.

## Versioning

No versioning of the script themselves, use as-is. They are writen in a way that they can be used with any post 7.x deployment.

## Authors

Thorben Jändling <<thorbenj@users.noreply.github.com>>

## License

AGPL 3

## Acknowledgments

Many colleagues at Elastic.co!
