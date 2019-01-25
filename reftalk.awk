#!/data/project/farotbot/local/bin/gawk -bE

#
# Talk pages needing a {{reflist-talk}}
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

}

function main(  i,a,j,bz,sz,ez,sp,z,command,dn,bm,la) {

  # batch mode. 0 = for testing small batch or single page. 1 = for production of all-pages
  bm = 0

  if(bm == 0) {

    # Single page mode. Set to 0 to disable single page mode, or set to name of article
    # sp = "Croix de Guerre"
    sp = 0

    # batch size. 1000 default
    bz = 1000

    # Start location. Set sz = "0" for first batch, "1000" for second etc..
    sz = 130000

    # End location. Set ez = "1000" for first batch, "2000" for second etc..
    ez = 200000

    for(z = sz + 1; z <= ez; z = z + bz) {

      if(!sp) { # batch mode

        command = Exe["tail"] " -n +" z " " G["dat"] "all-pages | " Exe["head"] " -n " bz " > " G["dat"] "runpages.new"
        sys2var(command)
        dn = z "-" z + (bz - 1)
        print dn " of " ez " " sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"") >> G["log"] "batch-done"
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

        if(sp !~ Re1)
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(sp)) ), sp)
        else
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/" urlencodeawk(sp)) ), sp)
        exit
      }
    }
  }

  # Production run all-pages
  #  Although loading all-pages into memory is consumptive, it's cheaper than the tail -n +line
  #  technique which is exspensive and slow when moving deeper into the file. Large batches would
  #  mitigate that some, but then there would be some missing towards the end.

  else if(bm == 1) {

    if( checkexists(G["dat"] "all-pages") ) {
      for(i = 1; i <= splitn(G["dat"] "all-pages", a, i); i++) {

        # Mark log every 1000 pages
        if(i / 1000 !~ /[.]/) {
          if(empty(la))
            la = length(a)  # How many total articles
          print i+1 "-" i+1000 " of " la " " sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"") >> G["log"] "all-pages-done"
          close(G["log"] "all-pages-done")
        }

        if(wikiname !~ Re1)
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/Talk:" urlencodeawk(a[i])) ), a[i])
        else
          reftalk(sys2var(Exe["wget"] " -q -O- " shquote("https://en.wikipedia.org/wiki/" urlencodeawk(a[i])) ), a[i])
      }
    }
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

          # Check for empty <ref></ref>
          origSec = arrSecW["1"]
          gsub(/[<]ref[>][ ]*[<][ ]*\/[ ]*ref[>]/, "", origSec)
          if(!match(stripnowikicom(origSec), /[<][ ]*ref[ ]*/)) {
            print wikiname " ---- " sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"") " ---- empty <ref></ref> in section \"" arrTOC[s] "\"" >> G["log"] "error"
            continue
          }

          # Check for a level-1 section that umbrellas in all level-2's below it - log and skip
          splitn(arrSecW["1"] "\n", b)
          if(b[1] ~ /[^=][=]$/) {
            print wikiname " ---- " sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"") " ---- Level-1 error in section \"" arrTOC[s] "\"" >> G["log"] "error"
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
            print wikiname " ---- " sys2var(Exe["date"] " +\"%Y%m%d-%H:%M:%S\"") " ---- gsubs() failure" >> G["log"] "error"
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

