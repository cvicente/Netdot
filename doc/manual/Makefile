# The master form of the documentation is the .txt file, which is converted
# to the other forms using pandoc <http://johnmacfarlane.net/pandoc/>
# The input is in pandoc's extended form of 'markdown'

PANDOC_OPTIONS=--number-sections --toc
PANDOC=pandoc
MARKDOWN2PDF=pandoc
INKSCAPE=inkscape
SED=sed

all: netdot-manual.htm netdot-manual.pdf netdot-manual.epub \
     netdot-manual-es.htm netdot-manual-es.pdf netdot-manual-es.epub

netdot-manual.htm: netdot-manual.txt
	$(PANDOC) $(PANDOC_OPTIONS) -s -o "$@" "$<"

netdot-manual-es.htm: netdot-manual-es.txt
	$(PANDOC) $(PANDOC_OPTIONS) -s -o "$@" "$<"

# Workaround for PDF output: any .svg images must be converted to .pdf first

SVG_IMAGES =
PDF_IMAGES =

%.pdf : %.svg
	$(INKSCAPE) --export-pdf "$@" "$<"

netdot-manual.pdf: netdot-manual.txt $(PDF_IMAGES)
	$(SED) 's/\.svg/.pdf/g' "$<" | $(MARKDOWN2PDF) $(PANDOC_OPTIONS) -f markdown -o "$@"

netdot-manual-es.pdf: netdot-manual-es.txt $(PDF_IMAGES)
	$(SED) 's/\.svg/.pdf/g' "$<" | $(MARKDOWN2PDF) $(PANDOC_OPTIONS) -f markdown -o "$@"

netdot-manual.epub: netdot-manual.txt $(SVG_IMAGES)
	$(PANDOC) $(PANDOC_OPTIONS) -s -o "$@" "$<"

netdot-manual-es.epub: netdot-manual-es.txt $(SVG_IMAGES)
	$(PANDOC) $(PANDOC_OPTIONS) -s -o "$@" "$<"

