#!/bin/bash
#
# mst-submit.sh
#
# Batch MST parsing.
#
# Loop over all of the corpora files (all the files in $CORPORA_DIR),
# and pass thier contents to the MST parser for processing and counting.
#
# ---------

# Load config parameters
if [ -z $MASTER_CONFIG_FILE ]; then
	echo "MASTER_CONFIG_FILE not defined!"
	exit -1
fi

if [ -r $MASTER_CONFIG_FILE ]; then
	source $MASTER_CONFIG_FILE
else
	echo "Cannot find master configuration file at MASTER_CONFIG_FILE"
	env |grep CONF
	exit -1
fi

if [ -r $MST_CONF_FILE ]; then
	echo "Start MST/MPG parsing"
else
	echo "Cannot find MST/MPG configuration file at MST_CONF_FILE"
	env |grep CONF
	exit -1
fi

notify_done () {
   echo -e "(finish-mst-submit)\n.\n." | nc $HOSTNAME $PORT >> /dev/null
}

# Verify that the input corpus can be found, and is not empty.
if [ ! -d $CORPORA_DIR ]; then
	echo "Cannot find a text corpus at $CORPORA_DIR"
	notify_done
	exit -1
fi

if [ 0 -eq `find $CORPORA_DIR -type f |wc -l` ]; then
	echo "Empty text corpus directory at $CORPORA_DIR"
	notify_done
	exit -1
fi

# Let guile know that we're starting with the pairs.
echo -e "(start-mst-submit)\n.\n." | nc $HOSTNAME $PORT >> /dev/null

${COMMON_DIR}/process-corpus.sh $MST_CONF_FILE

# The above won't return until all files have been submitted.
# Let guile know that we've finished with the submisions.
notify_done
