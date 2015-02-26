# Copyright 2012 Erlware, LLC. All Rights Reserved.
#
# This file is provided to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file
# except in compliance with the License.  You may obtain
# a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

ERLFLAGS= -pa $(CURDIR)/.eunit -pa $(CURDIR)/ebin -pa $(CURDIR)/deps/*/ebin

DEPS_PLT=$(CURDIR)/plt/deps_plt
DEPS=erts kernel stdlib

# =============================================================================
# Verify that the programs we need to run are installed on this system
# =============================================================================
ERL = $(shell which erl)
RELX = $(shell which relx)

ifeq ($(ERL),)
$(error "Erlang not available on this system")
endif

REBAR=$(shell which rebar)

ifeq ($(REBAR),)
$(error "Rebar not available on this system")
endif

.PHONY: all compile doc clean test dialyzer typer shell distclean pdf \
  update-deps clean-common-test-data rebuild

NODE_NAME = receiver@localhost
APP_CMD = $(ERL) $(ERLFLAGS) -config cepheid_receiver -boot start_sasl -s cepheid_receiver_app -sname $(NODE_NAME)

ifdef CEPHEID_DB_PER_BRANCH
BRANCH = $(shell git rev-parse --abbrev-ref HEAD)
ifneq ($(BRANCH),"master")
APP_CMD += -cepheid_receiver db_name "<<\"cepheid_development_$(subst -,_,$(BRANCH))\">>"
endif
endif

all: deps compile dialyzer

# =============================================================================
# Rules to build the system
# =============================================================================

deps: rebar.config
	$(REBAR) get-deps
	$(REBAR) compile
	touch deps

update-deps:
	$(REBAR) update-deps
	$(REBAR) compile
	touch deps

compile:
	$(REBAR) skip_deps=true compile

doc:
	$(REBAR) skip_deps=true doc

eunit: compile clean-common-test-data
	$(REBAR) skip_deps=true eunit

test: compile eunit

$(DEPS_PLT):
	@echo Building local plt at $(DEPS_PLT)
	@echo
	dialyzer --output_plt $(DEPS_PLT) --build_plt \
	   --apps $(DEPS) -r deps

dialyzer: $(DEPS_PLT)
	dialyzer --fullpath --plt $(DEPS_PLT) -Wrace_conditions --src src

typer:
	typer --plt $(DEPS_PLT) -r ./src -I ./include

shell: deps compile
# You often want *rebuilt* rebar tests to be available to the
# shell you have to call eunit (to get the tests
# rebuilt). However, eunit runs the tests, which probably
# fails (thats probably why You want them in the shell). This
# runs eunit but tells make to ignore the result.
	- @$(REBAR) skip_deps=true eunit
	@$(ERL) $(ERLFLAGS)

pdf:
	pandoc README.md -o README.pdf

clean:
	- rm -rf $(CURDIR)/test/*.beam
	- rm -rf $(CURDIR)/log/*
	- rm -rf $(CURDIR)/ebin
	$(REBAR) skip_deps=true clean

distclean: clean
	- rm -rf $(DEPS_PLT)
	- rm -rvf $(CURDIR)/deps

rebuild: distclean deps compile escript dialyzer test

run: deps compile
	$(APP_CMD) -s reloader +pc unicode

run-prod:
	$(APP_CMD) -noinput +Bd

remsh:
	erl -remsh $(NODE_NAME) -sname remsh@localhost -setcookie $(shell cat .erlang.cookie)

release: all
	rm -rf $(CURDIR)/rel
	relx -o rel

dump_test_db:
	mysqldump -u root --no-data --add-drop-database --databases cepheid_test > $(CURDIR)/test/cepheid_test.sql

load_test_db:
	mysql -u root < $(CURDIR)/test/cepheid_test.sql
