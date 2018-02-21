# The master form of the documentation is the .txt file, which is converted
# to the other forms using pandoc <http://pandoc.org>
# The input is in pandoc's extended form of 'markdown'
# Requirements:
# $ sudo apt-get install pandoc texlive-fonts-recommended texlive-latex-extra

PANDOC_OPTIONS=--number-sections --toc
PANDOC=/usr/bin/pandoc

SOURCES=netdot-manual.txt netdot-manual-es.txt

PDFS=$(SOURCES:.txt=.pdf)
HTMLS=$(SOURCES:.txt=.html)

all: $(PDFS) $(HTMLS)

%.pdf: %.txt
	$(PANDOC) $(PANDOC_OPTIONS) $< -o $@

%.html: %.txt
	$(PANDOC) $(PANDOC_OPTIONS) $< -o $@

