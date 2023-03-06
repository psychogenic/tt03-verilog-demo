###
###  *** Makefile for mapping a project in HDL to GDS and extra utils ***
###  Copyright (C) 2023 Pat Deegan, https://psychogenic.com
###
###  Make gds through openlane, info (stats), png, interactive docker shell...
###  more docs and demonstration on
###  https://inductive-kickback.com/2023/03/top-to-transistors-verilog-to-asic
###
###
###  This is just a collection of useful make targets, collected from
###  OpenLane, Tiny Tapeout github actions, and of my own to play around with 
###  the design hardening process.  Only tested under linux.
###
###  Ensure the verilog source(s) is/are under src/ and info.yaml has been edited
###  accordingly.
###
###  Note: designed to be run in project toplevel, some under OpenLane's
###  designs directory
###  .../path/to/OpenLane/designs/myproject
###
###  **** Useful targets ****
###
###  make gds # kickstart the openlane flow
###  make png # generate an image of GDS
###  make info # generate some stats on project
###
###  make interactive  # launch a shell into OpenLane, with project under /work
###  
###  make klayout_cells  # show generated GDS in klayout
###
###  make show_latestdb  # run openroad GUI with latest db
###
### 
###  *** Multiple Runs ***
###  By default, the flow run data will be tagged as 
###  runMMDD with the current date, e.g. run0314 or March 14th, to 
###  allow for multiple different runs to be kept around, but still
###  keep the makefile easy to use.  
###
###  The data will be collected in runs/ under this project directory
###
###  To override, or refer to 
###  a specific run, prefix your make with
###
###  FLOW_RUN_TAG=foobar make gds
###  FLOW_RUN_TAG=foobar make klayout_cells
###  
###  *** Notes ***
###  Use 
###   make -n TARGET
###  to do a dry run, and see what the actual commands executed would be
###
###  In the shell, from 
###   make interactive
###  the project directory is available under /work.  Also, the full command
###  to run the flow is in the env, as $FLOWRUNNER
###
###  
### Licensed under the Apache License, Version 2.0 (the "License");
### you may not use this file except in compliance with the License.
### You may obtain a copy of the License at
###
###      http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.
###


PYTHON_BIN ?= python3
CWD = $(shell pwd)


# OPENLANE_ROOT set this to full path of openlane install
# (dumb way to get an exact directory, no simlinks or ../)
OPENLANE_ROOT ?= $(shell cd ../../; pwd)

# PDK_ROOT set this to full path of sky130 pdk
PDK_ROOT ?= $(OPENLANE_ROOT)/pdks

OPENLANE_IMAGE_NAME ?= efabless/openlane

DOCKER_OPTIONS = $(shell $(PYTHON_BIN) $(OPENLANE_ROOT)/env.py docker-config)

DOCKER_ARCH ?= $(shell $(PYTHON_BIN) $(OPENLANE_ROOT)/docker/current_platform.py)

PDK ?= sky130A

# FLOW_RUN_TAG current run tag
# e.g. 
#      FLOW_RUN_TAG=trialXYZ make gds
# will gen all its output under runs/trialXYZ
FLOW_RUN_TAG ?= run$(shell date +"%m%d")

# WORKDIR parent dir with src etc, defaults to pwd
WORKDIR ?= $(shell pwd)

# INFOFILE -- result of make info, some stats output by 
# tt into summary-info-$(FLOW_RUN_TAG).txt
INFOFILE ?= $(WORKDIR)/summary-info-$(FLOW_RUN_TAG).txt


# x windows stuff for interactive
XSOCK :=/tmp/.X11-unix
XAUTH :=/tmp/.docker.xauth

# OPENLANE_SRC_WORKDIR -- the project dir is mapped into openlane docker at
# this location 
OPENLANE_SRC_WORKDIR ?= /work

# CURRENTRUN_OUTPUT_DIR -- where the output of the flow winds up
CURRENTRUN_OUTPUT_DIR := runs/$(FLOW_RUN_TAG)

# FLOW_RUNNER_COMMAND -- the actual call to flow.tcl, inside openlane docker
FLOW_RUNNER_COMMAND := ./flow.tcl -overwrite -design $(OPENLANE_SRC_WORKDIR)/src -run_path $(OPENLANE_SRC_WORKDIR)/runs -tag $(FLOW_RUN_TAG)

# basic openlane docker args, mounting for source files, setting up X forwarding
# (for interactive, e.g. openroad -gui), and a $FLOWRUNNER env var just as a reminder
OPENLANE_DOCKER_ARGS := -v $(OPENLANE_ROOT):/openlane \
		-v $(PDK_ROOT):$(PDK_ROOT) -v $(WORKDIR):$(OPENLANE_SRC_WORKDIR) \
		-e PDK_ROOT=$(PDK_ROOT)  -e PDK=$(PDK) \
		-u $(shell id -u $(USER)):$(shell id -g $(USER)) \
		--net=host --env="DISPLAY"  \
		-v $(XSOCK) -v $(XAUTH) -e XAUTHORITY=$(XAUTH) \
		-e FLOWRUNNER="$(FLOW_RUNNER_COMMAND)" \
		$(OPENLANE_IMAGE_NAME)


# some output file that shows gds was already run
GDS_RUN_OUTFILE := $(CURRENTRUN_OUTPUT_DIR)/reports/signoff/drc.rpt


# get the TinyTapeout tools and install reqs
tt: 
	git clone https://github.com/TinyTapeout/tt-support-tools.git tt
	pip install -r tt/requirements.txt


# generated user config, using tt
src/user_config.tcl: tt
	./tt/tt_tool.py --create-user-config
	

# make userconfig will gen this file
userconfig: src/user_config.tcl


# make the GDS, ie. go through entire flow
gds: src/user_config.tcl $(GDS_RUN_OUTFILE)
	

# a stats file post run
$(INFOFILE): 
	./tt/tt_tool.py --run-dir $(CURRENTRUN_OUTPUT_DIR) --print-warnings > $(INFOFILE)
	./tt/tt_tool.py --run-dir $(CURRENTRUN_OUTPUT_DIR) --print-stats >> $(INFOFILE)
	./tt/tt_tool.py --run-dir $(CURRENTRUN_OUTPUT_DIR) --print-cell-category >> $(INFOFILE)

# make info to generate stats file, after going through flow
info: gds $(INFOFILE)
	cat $(INFOFILE)
	echo "Stored in $(INFOFILE)"

# the PNG of all the magic
gds_render.png: 
	./tt/tt_tool.py --run-dir $(CURRENTRUN_OUTPUT_DIR)  --create-png

# make png, to get image
png: gds gds_render.png
	echo $(shell ls -1 gds_render*)

# make interactive, to launch openlane docker in interactive mode 
# trying my best to keep X happy and stable... mostly ok. mostly.
interactive: tt
	xauth nlist $(DISPLAY) | sed -e 's/^..../ffff/' | xauth -f $(XAUTH) nmerge -
	chmod 755 $(XAUTH)
	docker run -it  $(OPENLANE_DOCKER_ARGS)

# not the best way to do this, but simple way of detecting GDS has
# been done
$(GDS_RUN_OUTFILE):
	echo running synth
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "$(FLOW_RUNNER_COMMAND)"
	
.PHONY: klayout_cells show_latestdb
klayout_cells: 
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "klayout -l $(OPENLANE_SRC_WORKDIR)/.klayout-cellfocused.lyp $(OPENLANE_SRC_WORKDIR)/$(CURRENTRUN_OUTPUT_DIR)/results/final/gds/*.gds"


show_latestdb:
	echo read_db $(OPENLANE_SRC_WORKDIR)/`find $(CURRENTRUN_OUTPUT_DIR) -name "*.odb" | xargs ls -1t | head -1` > $(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl
	echo gui::show >> $(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "openroad $(OPENLANE_SRC_WORKDIR)/$(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl"


# delete that GDS outfile and 
.PHONY: clean veryclean
clean:
	rm -f $(WORKDIR)/$(GDS_RUN_OUTFILE)
	rm -f gds_render.png
	rm -f $(INFOFILE)

veryclean:
	rm -r $(CURRENTRUN_OUTPUT_DIR)

