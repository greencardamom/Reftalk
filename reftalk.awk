#!/data/project/farotbot/local/bin/gawk -bE

#
# Talk pages needing a {{reflist-talk}}
#
#  https://github.com/greencardamom/Reftalk
#

# The MIT License (MIT)
#
# Copyright (c) 2019 by User:GreenC (at en.wikipedia.org)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# set bot name before @includes
BEGIN {
  BotName = "reftalk"
}

@include "botwiki.awk"
@include "atools.awk"
@include "json.awk"
@include "library.awk"

BEGIN {

  IGNORECASE = 1

  delete G

  G["path"]   = Home                    # Defined in botwiki.awk
  G["dat"]    = G["path"] "dat/"
  G["static"] = G["path"] "static/"
  G["log"]    = G["path"] "log/"

  Re1 = "^(Wikipedia talk[:]|User talk[:])"

  loadtemplates()

  main()

  exit 0

}

function main(  i,a,j,bz,sz,ez,sp,z,command,dn,bm,la,startpoint,offset,endall,bl,article,al,artblock) {

  # batch mode. 0 = for testing small batch or single page. 1 = for production of all-pages
  bm = 1

  if(bm == 0) {

    # Single page mode. Set to 0 to disable single page mode, or set to name of article
    # sp = "Wikipedia talk:Bots/Requests for approval/GreenC bot 8"
    # sp = "Hydraulic fracturing by country"
    sp = 0

    # batch size. 1000 default
    bz = 1000

    # Start location. Set sz = "0" for first batch, "1000" for second etc..
    sz = 130000

    # End location. Set ez = "1000" for first batch, "2000" for second etc..
    ez = 200000

    for(z = sz + 1; z <= ez; z = z + bz) {

      if(!sp) { # batch mode

        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

        command = Exe["tail"] " -n +" z " " G["dat"] "all-pages | " Exe["head"] " -n " bz " > " G["dat"] "runpages.new"
        sys2var(command)

        dn = z "-" z + (bz - 1)
        print dn " of " ez " " CurTime >> G["log"] "batch-done"
        close(G["log"] "batch-done")

        if( checkexists(G["dat"] "runpages.new") ) {
          for(i=1; i <= splitn(G["dat"] "runpages.new", a, i); i++) {
            # stdErr("Processing " a[i])
            if(wikiname !~ Re1)
              reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(a[i])) ), a[i])
            else
              reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/" urlencodeawk(a[i])) ), a[i])
          }
        }
      }

      else {  # single page mode

        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

        if(sp !~ Re1)
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(sp)) ), sp)
        else
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/" urlencodeawk(sp)) ), sp)
        exit 0
      }
    }
  }

  # Run all-pages
  #  Below method designed to minimize memory on Toolforge grid, keep log files small, and gracefully handle
  #  frequent stops by the Grid. But also works as-is on any server.
  #   all-pages = file containing complete list of millions of article titles. See setup instructions.
  #   all-pages.done = permanent log. One line equates to 1000 articles processed.
  #   all-pages.offset = temporary log. One line equates to one article processed. This rolls over with
  #                      each new 1000 block. If the bot halts mid-way through, it will pick up where left off.

  else if(bm == 1) {

    # Establish startpoint ie. the line number in all-pages where processing will begin

    # To manually set startpoint. Set along a 1000 boundary ending in 1 eg. 501001 OK. 501100 !OK
    # startpoint = 202001

    # To auto pick-up where it left-off, find startpoint in all-pages.done
    if(empty(startpoint) && checkexists(G["log"] "all-pages.done")) {
      startpoint = sys2var(Exe["tail"] " -n 1 " G["log"] "all-pages.done | " Exe["grep"] " -oE \"^[^-]*[^-]\"")

      if(startpoint ~ /endall/) {    # reached the end
        sys2var(Exe["mailx"] " -s " shquote("NOTIFY: " BotName " already reached the end. Aborted run.") " " UserEmail " < /dev/null")
        exit 0
      }

      if(!isanumber(startpoint)) {  # log corrupted
        sys2var(Exe["mailx"] " -s " shquote("NOTIFY: " BotName " unable to restart") " " UserEmail " < /dev/null")
        exit 0
      }

      CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")
      print CurTime " ---- Bot (re)start (" startpoint "-" startpoint + 999 ")" >> G["log"] "restart"
      close(G["log"] "restart")
    }

    # All else fails (eg. first run) start at 1
    if(empty(startpoint))
      startpoint = 1

    if (checkexists(G["dat"] "all-pages") ) {

      # Check for offset ie. bot halted mid-way through a block
      if (checkexists(G["log"] "all-pages.offset")) {
        offset = wc(G["log"] "all-pages.offset")
        if(offset == 0 || offset == 1000)
          offset = 1
        removefile2(G["log"] "all-pages.offset")
      }
      else
        offset = 1

      # Iterate through all-pages creating blocks of 1000 articles each
      for(bl = startpoint; bl > 0; bl += 1000) {

        # Retrieve a 1000 block from all-pages
        artblock = sys2var(Exe["tail"] " -n +" bl " " G["dat"] "all-pages | " Exe["head"] " -n 1000")

        # Reached end of all-pages
        if(length(artblock) < 1000)
          endall = 1

        # Log block at all-pages.done
        CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")
        print bl "-" bl+999 " " CurTime >> G["log"] "all-pages.done"
        close(G["log"] "all-pages.done")

        # Iterate through 1..1000 individual articles in artblock
        for(al = offset; al <= splitn(artblock "\n", article, al, offset); al++) {

          # Log offset file
          print al >> G["log"] "all-pages.offset"
          close(G["log"] "all-pages.offset")

          # Log debug file (optional)
          # print bl "-" bl+999 " " al >> G["log"] "all-pages.debug"
          # close(G["log"] "all-pages.debug")

          # Run reftalk on given article title
          if(wikiname !~ Re1)
            reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(article[al])) ), article[al])
          else
            reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/" urlencodeawk(article[al])) ), article[al])
        }

        # Successful completion of 1000 articles, clear offset file
        removefile2(G["log"] "all-pages.offset")
        offset = 1

        # Reached end of all-pages, quit
        if(endall) {
          print "endall" >> G["log"] "all-pages.done"
          break
        }
      }
    }
    sys2var(Exe["mailx"] " -s " shquote("NOTIFY: " BotName " has completed processing all articles!") " " UserEmail " < /dev/null")
  }
}

#
# Determine if there is a missing reflist template anywhere on the page
#
function reftalk(wikihtml, wikiname,   tfp,i,j,k,l,fp) {

  tfp = stripwikicomments(wikihtml)
  j = gsub(/<[ ]*ol[ ]*class[ ]*[=][ ]*"references"[ ]*[>]/, "", tfp)
  if(wikiname !~ Re1)
    fp = sys2var(Exe["wikiget"] " -w " shquote("Talk:" wikiname) )
  else
    fp = sys2var(Exe["wikiget"] " -w " shquote(wikiname) )
  tfp = stripnowikicom(fp)
  if(gsub(G["templates"], "", tfp) < j) {
    addreftalk(fp, wikiname)
    return 1
  }
  return 0

}

#
# Go through each section checking for the canidate
#
function addreftalk(wikisource, wikiname,  jsoninTOC,jsonaTOC,arrTOC,jsoninSecW,jsonaSecW,arrSecW,s,a,mid,i,out,summary,edcnt,origWS,origSec,apiname,b) {

  if(wikiname !~ Re1)
    apiwikiname = "Talk:" wikiname
  else
    apiwikiname = wikiname

  # Get index of sections, then step through each one looking for a missing {{relist}} in the content

  jsoninTOC = sys2var("wget -q -O- " shquote("https://en.wikipedia.org/w/api.php?action=parse&page=" urlencodeawk(apiwikiname) "&prop=sections&format=json&formatversion=2&maxlag=5"))

  if( query_json(jsoninTOC, jsonaTOC) >= 0) {

    # awkenough_dump(jsonaTOC, "jsonaTOC")
    # jsona["parse","sections","2","line"]=Please do not "correct" the statement about universal donors

    splitja(jsonaTOC, arrTOC, 3, "line")

    for(s in arrTOC) {

      if(jsonaTOC["parse","sections",s,"toclevel"] != 1) continue # skip if not a 1st level section ie. == <section> ==

      jsoninSecW = sys2var("wget -q -O- " shquote("https://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&rvlimit=1&titles=" urlencodeawk(apiwikiname) "&rvsection=" s "&format=json&formatversion=2&maxlag=5"))

      if( query_json(jsoninSecW, jsonaSecW) >= 0) {

        # awkenough_dump(jsonaSecW, "jsonaSecW")
        # jsona2["query","pages","1","revisions","1","slots","main","content"]=

        splitja(jsonaSecW, arrSecW, 5, "content")

        # print "title   = " arrTOC[s]
        # print "content = " arrSecW["1"]

        if(match(stripnowikicom(arrSecW["1"]), /[<][ ]*ref[ ]*/) && match(stripnowikicom(arrSecW["1"]), /[<][ ]*\/[ ]*ref[ ]*[>]/) && ! match(stripnowikicom(arrSecW["1"]), G["templates"]) ) {

          CurTime = sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"")

          # Check for empty <ref></ref>
          origSec = arrSecW["1"]
          gsub(/[<]ref[>][ ]*[<][ ]*\/[ ]*ref[>]/, "", origSec)
          if(!match(stripnowikicom(origSec), /[<][ ]*ref[ ]*/)) {
            print wikiname " ---- " CurTime " ---- empty <ref></ref> in section \"" arrTOC[s] "\"" >> G["log"] "error"
            continue
          }

          # Check for a level-1 section that umbrellas in all level-2's below it - log and skip
          splitn(arrSecW["1"] "\n", b)
          if(b[1] ~ /[^=][=]$/) {
            print wikiname " ---- " CurTime " ---- Level-1 error in section \"" arrTOC[s] "\"" >> G["log"] "error"
            continue
          }

          # Determine if line-break needed between body of text and template
          i = splitn(arrSecW["1"], a)
          if(empty(a[i]))
            mid = ""
          else
            mid = "\n"

          # Add the template, check and log if error
          out = arrSecW["1"] mid "\n{{reflist-talk}}"
          origWS = wikisource
          wikisource = gsubs(arrSecW["1"], out, wikisource)
          if(origWS == wikisource) {
            print wikiname " ---- " CurTime " ---- gsubs() failure" >> G["log"] "error"
            continue
          }
          edcnt++

          # mis-match caused by transclusions
          if( ! match(arrSecW["1"], "[=]{1,2}[ ]*" regesc3(arrTOC[s]))) {
            arrTOC[s] = strip(a[1])
            gsub(/^[=]{1,2}[ ]*|[ ]*[=]{1,2}$/, "", arrTOC[s])
          }

          if(empty(summary))
            summary = "{{[[Template:reflist-talk|reflist-talk]]}} to [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
          else
            summary = summary " and [[" urlencodeawk(apiwikiname) "#" urlencodeawk(arrTOC[s]) "|#" arrTOC[s] "]]"
        }
      }
    }
  }

  if(summary) {

    if(length(summary) > 400) {  # Exceeds limit see Help:Edit_summary#The_500-character_limit
      if(edcnt > 1)
        summary = "Add " edcnt " {{[[Template:reflist-talk|reflist-talk]]}} (via [[User:GreenC bot/Job 8|reftalk]] bot)"
      else
        summary = "Add 1 {{[[Template:reflist-talk|reflist-talk]]}} (via [[User:GreenC bot/Job 8|reftalk]] bot)"
    }
    else {
      if(edcnt > 1)
        summary = "Add " edcnt " " summary " (via [[User:GreenC bot/Job 8|reftalk]] bot)"
      else
        summary = "Add " summary " (via [[User:GreenC bot/Job 8|reftalk]] bot)"
    }

    upload(wikisource, apiwikiname, summary, G["log"], BotName, "en")
  }
}

#
# Load ~static/templates into G["templates"] - if a template is found, assume it has a ref
#  To create the templates file see 0README in ~static
#
function loadtemplates(  i,a,respace) {

  for(i = 1; i <= splitn(G["static"] "templates", a, i); i++)
    G["templates"] = G["templates"] "|" regesc3(a[i]) "|" regesc3("template:" a[i])
  gsub(/^[|]|[|]$/, "", G["templates"])
  G["templates"] = "([{][{][ \\n]*[ ]*(" G["templates"] "))|([<][ ]*references)"

}

