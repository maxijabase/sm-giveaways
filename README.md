# sm-giveaways
A SourceMod plugin to make giveaways.

## Cvars
* `sm_giveaways_version` - Plugin version
* `sm_giveaways_sounds` - Whether the plugin should play sounds upon starting, entering, and ending a giveaway (Default: 1)
* `sm_giveaways_time` - Time in seconds before plugin stops the giveaway and announces the winner (Default: 60)
* `sm_giveaways_winner_cooldown` - Amount of giveaways that must pass before the winner of a giveaway has the chance to win again (Default: 1)

## Commands

Admin Commands
* `sm_gstart [item]` - Start a giveaway
* `sm_gstop` - End a giveaway
* `sm_gcancel` - Cancel a giveaway
* `sm_gparticipants` - See the list of participants of the current giveaway

User commands
* `sm_enter` - Enter a giveaway!
* `sm_leave` - Leave the giveaway!
