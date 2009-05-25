// Console: shift_margins
// Description: shift margins left and right
/**** The preceding lines are pdfedit magic! do not remove them! ***/

/*
 * Shift pages alternately left or right, and add page numbers in the
 * outer corners.
 *
 * This is a QSA script for pdfedit. QSA is a (deprecated) dialect of
 * ecmascript used for scripting QT applications like pdfedit.
 *
 */

const DEFAULT_OFFSET = 25;
/* FLOSS Manuals default book size at lulu: 'Comicbook', 6.625" x 10.25" */
const COMIC_WIDTH = (6.625 * 72);
const COMIC_HEIGHT = (10.25 * 72);

const PAGE_NUMBER_SIZE = 12;

const DEFAULT_DIR = 'LTR';

//const DEFAULT_MODE = 'TRANSFORM';
//const DEFAULT_MODE = 'MEDIABOX';
const DEFAULT_MODE = 'COMICBOOK';
const DEFAULT_NUMBER_STYLE = 'roman';

function transform_page(page, offset){
    page.setTransformMatrix([1, 0, 0, 1, offset, 0]);
}

function rotate_page180(page){
    /* From the PDF reference:
     *
     * Rotations are produced by
     *  [cos(theta) sin(theta) −sin(theta) cos(theta) 0 0],
     * which has the effect of rotating the coordinate
     * system axes by an angle theta counterclockwise.
     *
     * but the rotation is about the 0,0 axis: ie the top left.
     * So addin the width and height is necessary.
     *
     * There is *also* a Rotate key in the page or document dictionary
     * that can be used to rotate in multiples of 90 degrees. But I did
     * not find that first, and it fails mysteriously in pdfedit.
     *
     *     var d = page.getDictionary();
     *     d.add('Rotate', createInt(180));
     *
     */
    var box = page.mediabox();
    //print("box is " + box);

    angle = Math.PI ;
    var c = Math.cos(angle);
    var s = Math.sin(angle);
    page.setTransformMatrix([c, s, -s, c, box[2], box[3]]);
}


function shift_page_mediabox(page, offset, width, height){
    var box = page.mediabox();
    var x = box[0];
    var y = box[1];
    var w = box[2] - box[0];
    var h = box[3] - box[1];

    if (width || height){
        /*resize each page, so put the mediabox out and up by half of
        the difference.
         XXX should the page really be centred vertically? */
        x -= 0.5 * (width - w);
        y -= 0.5 * (height - h);
        w = width;
        h = height;
        //print("now x, y = " + x + ", " + y);
    }
    page.setMediabox(x - offset, y, x + w - offset, y + h);
}


/*
 * Helper functions for creating pdf operators. You can create an
 * IPropertyArray or a PdfOperator like this:
 *
 * var array = iprop_array("Nnns", "Name", 1, 1.2, "string"); var rg =
 * operator('rg', "nnn", 0, 1, 0);
 *
 * where the first argument to operator and the second to iprop_array
 * is a template (ala Python's C interface) that determines the
 * interpretation of subsequent parameters. Common keys are 'n' for
 * (floaing point) number, 's' for string, 'N' for name, 'i' for
 * integer. See the convertors object below.
 *
 */

var convertors = {
    a: createArray,
    b: createBool,
    //c: createCompositeOperator,
    d: createDict,
    o: createEmptyOperator,
    i: createInt,
    N: createName,
    O: createOperator,
    n: createReal,
    r: createRef,
    s: createString,
    z: function(x){ return x; } //for pre-existing object, no processing.
};

function iprop_array(pattern){
    //print("doing " + arguments);
    var array = createIPropertyArray();
    for (i = 1; i < arguments.length; i++){
        var s = pattern.charAt(i - 1);
        var arg = arguments[i];
        var op = convertors[s](arg);
        array.append(op);
    }
    return array;
}

function operator(op){
    var array = iprop_array(arguments.slice(1));
    return createOperator(op, array);
}

/* roman_number(number) -> lowercase roman number + approximate width */
function roman_number(number){
    var data = [
        'm', 1000,
        'd', 500,
        'c', 100,
        'l', 50,
        'x', 10,
        'v', 5,
        'i', 1
    ];

    var i;
    var s = '';
    for (i = 0; i < data.length; i += 2){
        var value = data[i + 1];
        var letter = data[i];
        while (number >= value){
            s += letter;
            number -= value;
        }
    }

    var subs = [
        'dcccc', 'cm',
        'cccc', 'cd',
        'lxxxx', 'xc',
        'xxxx', 'xl',
        'viiii', 'ix',
        'iiii', 'iv'
    ];
    for (i = 0; i < subs.length; i+= 2){
        s = s.replace(subs[i], subs[i + 1]);
    }

    /* Try to take into account variable widths.
     * XXX these numbers are made up, and font-specific.
     */
    var widths = {
        m: 0.9,
        d: 0.6,
        c: 0.6,
        l: 0.3,
        x: 0.6,
        v: 0.6,
        i: 0.3
    };

    var w = 0;
    for (i = 0; i < s.length; i++){
        w += widths[s.charAt(i)];
    }

    return {
        text: s,
        width: w
    };
}


/* change_number_charset(number, charset) -> unicode numeral + approx. width
 farsi =  '۰۱۲۳۴۵۶۷۸۹';
 arabic = '٠١٢٣٤٥٦٧٨٩';
 */
function change_number_charset(number, charset){
    var charsets = {
        arabic: ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'],
        farsi:  ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹']
    };
    if (charset == undefined)
        charset = 'arabic';
    var numerals = charsets[charset];
    var west = number.toString();
    var i;
    var s = '';
    for (i = 0; i < west.length; i++){
        var c = west.charAt(i);
        s += numerals[parseInt(c)];
    }
    //lazy guess at width
    var w = 0.6 * s.length;
    return {
        text: s,
        width: w
    };
}

function latin_number(number){
    var text = number.toString();
    /* It would be nice to know the bounding box of the page number,
     but it is not rendered during this process, so we have to guess.
     All Helvetica numerals are the same width (approximately N shape)
     so I'll assume 0.6ish.
     */
    return {
        text: text,
        width: text.length * 0.6
    };
}

var stringifiers = {
    roman:  roman_number,
    arabic: change_number_charset,
    farsi:  change_number_charset,
    latin:  latin_number
};

function add_page_number(page, number, dir, style){
    print(' ' + number + ' ' +  dir + ' ' + style);
    if (! style in stringifiers || style == undefined){
        style = 'latin';
    }
    var box = page.mediabox();
    var h = PAGE_NUMBER_SIZE;
    var n = stringifiers[style](number, style);
    var text = n.text;
    var w = n.width * h;

    var y = box[1] + 20 - h * 0.5;
    var x = box[0] + 60;

    if ((number & 1) == (dir != 'RTL')){
        x = box[2] - x - w;
    }

    var q = createCompositeOperator("q", "Q");
    var BT = createCompositeOperator("BT", "ET");

    /* it would be nice to use the book's font, but it seems not to
    work for unknown reasons.  */
    page.addSystemType1Font("Helvetica");
    var font = page.getFontId("Helvetica"); // probably 'PDFEDIT_F1'

    var rg = createOperator("rg", iprop_array('nnn', 0.5, 0, 0));
    var tf = createOperator("Tf", iprop_array('Nn', font, h));
    var td = createOperator("Td", iprop_array('nn', x, y));
    var tj = createOperator("Tj", iprop_array('s', text));
    var et = createOperator("ET", iprop_array());
    var end_q = createOperator("Q", iprop_array());

    BT.pushBack(rg, BT);
    BT.pushBack(tf, rg);
    BT.pushBack(td, tf);
    BT.pushBack(tj, td);
    BT.pushBack(et, tj);

    q.pushBack(BT, q);
    q.pushBack(end_q, BT);


    /* Webkit applies a transformation matrix so it can write the pdf
     * using its native axes.  That means, to use the default grid we
     * need to either insert the page number before the webkit matrix,
     * or apply an inverse.  The inverse looks like:
     *
     * createOperator("cm", iprop_array('nnnnnn', 16.66667, 0, 0, -16.66667, -709.01015, 11344.83908));
     *
     * but it is simpler to jump in first.
     */

    var stream = page.getContentStream(0);
    var iter = stream.getFirstOperator().iterator();
    var op;
    do {
        op = iter.current();
        if (op.getName() == 'cm'){
            //print("found cm operator " + op);
            //need to step back one
            iter.prev();
            op = iter.current();
            break;
        }
    } while (iter.next());

    stream.insertOperator(op, q);
}



function number_pdf_pages(pdf, dir, number_style, number_start){
    var pages = pdf.getPageCount();
    var i;
    var offset = 0;
    if (number_start.charAt(0) == '_')
        number_start = '-' + number_start.substring(1);
    
    var start = parseInt(number_start) || 1;
    if (start < 0){
        /*count down (-start) pages before beginning */
        offset = -start;
        start = 1;
    }
    else {
        /* start numbering at (start) */
        offset = 1 - start;
    }
    for (i = start; i <= pages - offset; i++){
        add_page_number(pdf.getPage(i + offset), i, dir, number_style);
    }
}


function process_pdf(pdf, offset, func, width, height){
    var pages = pdf.getPageCount();
    var i;
    for (i = 1; i <= pages; i++){
        func(pdf.getPage(i), offset, width, height);
        offset = -offset;
    }
}


function shift_margins(pdfedit, offset_s, filename, mode, dir, number_style, number_start){
    print("got " + arguments.length + " arguments: ");
    for (var i = 0; i < arguments.length; i++){
        print(arguments[i]);
    }

    var offset = parseFloat(offset_s);
    if (isNaN(offset)){
        print ("offset not set or unreadable ('" + offset_s + "' -> '" + offset +"'), using default of " + DEFAULT_OFFSET);
        offset = DEFAULT_OFFSET;
    }

    mode = mode || DEFAULT_MODE;
    mode = mode.upper();
    dir = dir || DEFAULT_DIR;
    dir = dir.upper();
    number_style = number_style || DEFAULT_NUMBER_STYLE;
    number_style = number_style.lower();

    /* Rather than overwrite the file, copy it first to a similar name
    and work on that ("saveas" doesn't work) */
    var newfilename;
    if (filename == undefined){
        newfilename = '/tmp/test-src.pdf';
        filename = '/home/douglas/fm-data/pdf-tests/original/farsi-wk-homa.pdf';
        print("using default filenamer of " + newfilename);
    }
    else {
        var re = /^(.+)\.pdf$/i;
        var m = re.search(filename);
        if (m == -1){
            print(filename + " doesn't look like a pdf filename");
            exit(1);
        }
        newfilename = re.cap(1) + '-' + mode + '.pdf';
    }
    Process.execute("cp " + filename + ' ' + newfilename);

    var pdf = pdfedit.loadPdf(newfilename, 1);


    /* add on page numbers */
    if (number_style != 'none'){
        number_pdf_pages(pdf, dir, number_style, number_start);
    }

    /* RTL book have gutter on the other side */
    /*rotate the file if RTL*/
    if (dir == 'RTL'){
        //offset = -offset;
        process_pdf(pdf, offset, rotate_page180);
    }


    if (mode == 'TRANSFORM')
        process_pdf(pdf, offset, transform_page);
    else if (mode == 'MEDIABOX')
        process_pdf(pdf, offset, shift_page_mediabox);
    else if (mode == 'COMICBOOK')
        process_pdf(pdf, offset, shift_page_mediabox, COMIC_WIDTH, COMIC_HEIGHT);


    pdf.save();
    pdf.unloadPdf();
}



/* This file gets executed *twice*: once as it gets loaded and again
 as it gets "called". The first time it recieves an extra command line
 parameter -- the name of the "function", which is the name of the
 script (or an abbreviation thereof).

 The first real parameter is the offset (a number), so it is easy to
 detect the spurious "function" parameter and do nothing in that case.

*/

print("in shift_margins");

var p = parameters();

if (p.length == 0 || ! p[0].startsWith("shi")){
    var i;
    for (i = 0; i < p.length; i++){
        print(p[i]);
    }

    /* There is no _apply_ method for functions in QSA !!  and
     * indexing past the end of an array is an error.  So fill it out
     * with some undefineds to fake variadic calling.
     */
    for (i = 0; i < 9; i++){
        p.push(undefined);
    }
    shift_margins(this, p[0], p[1], p[2], p[3], p[4], p[5], p[6]);
}
else {
    print("skipping first round");
}



