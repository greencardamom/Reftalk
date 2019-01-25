Reftalk
===================
by User:GreenC (en.wikipedia.org)
Copyright 2019
MIT License

Info
========
Reftalk is a Wikipedia bot that checks talks pages for instances where the template {{reftalk}} would be useful. It adds it to multiple sections as needed.

See [WP:Bots/Requests for approval/GreenC bot 8](https://en.wikipedia.org/wiki/Wikipedia:Bots/Requests_for_approval/GreenC_bot_8)

Requirements
========
* GNU Awk 4.1+
* [BotWikiAwk](https://github.com/greencardamom/BotWikiAwk) (version Jan 2019 +)

Installation
========

1. Install BotWikiAwk and follow setup instructions. Add OAuth credentials to wikiget.

2. Clone Reftalk. For example:
	git clone https://github.com/greencardamom/Reftalk

3. Edit ~/BotWikiAwk/lib/botwiki.awk

	A. Set local URLs in section #1 and #2 

	B. Create a new 'case' entry in section #3, adjust the Home bot path created in step 3:

		case "reftalk":                                             # Custom bot paths
			Home = "/data/project/projectname/Reftalk/"         # path ends in "/"
			Agent = UserPage " (ask me about " BotName ")"
			break

	C. Add a new entry in section #10 (inside the statement if(BotName != "makebot") {} )

		if(BotName !~ /reftalk/) {
			delete Config
			readprojectcfg()
		}

4. Follow instructions in ~/Reftalk/static/0README to download the list of templates the bot will ignore
5. Set ~/Reftalk/reftalk to mode 750, set the first shebang line to location of awk

Running
========

1. Download a complete list of "all-pages" (takes a while)

     A. On Toolforge:

       /usr/bin/qsub -l mem_free=2G,h_vmem=2G -cwd -sync y -e /data/project/botwikiawk/Reftalk/dat/wikiget.stderr -o /data/project/botwikiawk/Reftalk/dat/all-pages /data/project/botwikiawk/BotWikiAwk/bin/wikiget -A -t 2 -k 0

     B. On other servers:

       wikiget -A -t 2 -k 0 > /data/project/botwikiawk/Reftalk/dat/all-pages

2. Configure settings for the run:

     Modify reftalk.awk main()

       If testing a single article
         bm = 0
         sp = "Siberian Tiger"
       If testing a range (eg. first 10,000 pages from all-pages):
         bm = 0
         sp = 0
         bz=1000, sz=0, ez=10000, sp=0
       If running the complete "all-pages":
         bm = 1

3. Run reftalk

     If running on Toolforge from the command-line:

       /usr/bin/qsub -l mem_free=2G,h_vmem=2G -e /data/project/botwikiawk/reftalk/reftalk.stderr -o /data/project/botwikiawk/reftalk/reftalk.stdout -V -wd /data/project/botwikiawk/reftalk /data/project/botwikiawk/reftalk/reftalk.awk

     If running on Toolforge from cron, the crontab would contain:

       SHELL=/bin/bash
       PATH=/sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin:/data/project/botwikiawk/BotWikiAwk/bin
       AWKPATH=.:/data/project/botwikiawk/BotWikiAwk/lib
       MAILTO= an email address for reporting when cron runs
       HOME=/data/project/botwikiawk
       LANG=en_US.UTF-8
       LC_COLLATE=en_US.UTF-8
       37 5 * * 7 /usr/bin/qsub -l mem_free=2G,h_vmem=2G -e /data/project/botwikiawk/reftalk/reftalk.stderr -o /data/project/botwikiawk/reftalk/reftalk.stdout -V -wd /data/project/botwikiawk/reftalk /data/project/botwikiawk/reftalk/reftalk.awk

     If running from anywhere else (home server etc):

       ./reftalk.awk > /data/project/botwikiawk/Reftalk/reftalk.stdout

4. Monitor ~/Reftalk/logs 


