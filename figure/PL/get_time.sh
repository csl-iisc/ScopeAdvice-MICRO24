#!/bin/bash

folder='eval'
out='run.out'

base='baseline'
onet1b='1t1b'
one2tnb='12tnb'
sam='sampling'
sa='scopeadvice'
blank='blank'

cat $folder/$base/$out | grep 'runtime' | awk '{ print $10 }' > $folder/$base".out"
cat $folder/$onet1b/$out | grep 'E2E' | awk '{ print $3 }' > $folder/$onet1b".out"
cat $folder/$one2tnb/$out | grep 'E2E' | awk '{ print $3 }' > $folder/$one2tnb".out"
cat $folder/$sam/$out | grep 'E2E' | awk '{ print $3 }' > $folder/$sam".out"
cat $folder/$sa/$out | grep 'E2E' | awk '{ print $3 }' > $folder/$sa".out"
cat $folder/$blank/$out | grep 'E2E' | awk '{ print $3 }' > $folder/$blank".out"