#!/usr/bin/env python3
"""Draws a sticker in the style of the WorkNexus pack (App/Resources/Stickers/WorkNexus): a tilted card with a white
border and a hard shadow, white text (SF Rounded Heavy; "|" breaks the line) and a round badge with an icon.

  python3 Scripts/make-sticker.py "Ko Cần Biết!" 214,51,132 /System/Library/Fonts/SFNSRounded.ttf out.png Heavy eye_off 3.5
  python3 Scripts/make-sticker.py "Gửi cái tên|ai làm" 52,73,94 /System/Library/Fonts/SFNSRounded.ttf out.png Heavy person -3

Arguments: text, card colour (r,g,b), font, output, font variation, icon (eye_off | person | heart_off | siren), tilt in degrees.
Needs Pillow. A new file in the WorkNexus pack must also be excluded in Scripts/sync-assets.sh.
"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
K=4
def make(text, color, font_path, out, angle=3.5, variation=None, size=40, icon='eye_off'):
    W=256*K
    canvas=Image.new('RGBA',(W,W),(0,0,0,0))
    cx,cy=130*K,128*K; w,h=203*K,108*K; r=20*K; b=8*K
    # card layer: border + fill + text, drawn level and rotated together
    card=Image.new('RGBA',(W,W),(0,0,0,0)); d=ImageDraw.Draw(card)
    d.rounded_rectangle((cx-w/2-b,cy-h/2-b,cx+w/2+b,cy+h/2+b),r+b,fill=(255,255,255,255))
    d.rounded_rectangle((cx-w/2,cy-h/2,cx+w/2,cy+h/2),r,fill=color)
    font=ImageFont.truetype(font_path,size*K)
    if variation: font.set_variation_by_name(variation)
    lines=text.split("|")
    def measure(font):
        boxes=[d.textbbox((0,0),l,font=font) for l in lines]
        return boxes, max(b[2]-b[0] for b in boxes)
    boxes,tw=measure(font)
    while tw>w-26*K:
        size-=1; font=ImageFont.truetype(font_path,size*K)
        if variation: font.set_variation_by_name(variation)
        boxes,tw=measure(font)
    lh=size*K*1.12
    total=lh*len(lines)
    asc,desc=font.getmetrics()
    for i,(l,b) in enumerate(zip(lines,boxes)):
        lw_=b[2]-b[0]
        y=cy-total/2+i*lh+(lh-(asc+desc))/2+(6 if len(lines)>1 else 3)*K
        d.text((cx-lw_/2-b[0], y), l, font=font, fill=(255,255,255,255))
    card=card.rotate(angle,resample=Image.BICUBIC,center=(cx,cy))
    # hard shadow of the card, 8px down
    a=card.split()[3].point(lambda v: 64 if v>128 else 0)
    shadow=Image.new('RGBA',(W,W),(0,0,0,0)); shadow.putalpha(a)
    canvas.alpha_composite(shadow,(0,8*K))
    canvas.alpha_composite(card)
    # badge
    bx,by,br=215*K,69*K,33*K
    sh=Image.new('RGBA',(W,W),(0,0,0,0)); ImageDraw.Draw(sh).ellipse((bx-br,by-br+4*K,bx+br,by+br+4*K),fill=(0,0,0,50))
    sh=sh.filter(ImageFilter.GaussianBlur(2*K)); canvas.alpha_composite(sh)
    bd=ImageDraw.Draw(canvas); bd.ellipse((bx-br,by-br,bx+br,by+br),fill=(255,255,255,255))
    if icon=='siren':
        # an alarm light with rays ("heads up"), in the card colour
        s_=K; ic=Image.new('RGBA',(W,W),(0,0,0,0)); idr=ImageDraw.Draw(ic)
        hx,hy=bx,by+4*s_
        idr.pieslice((hx-12*s_,hy-14*s_,hx+12*s_,hy+10*s_),180,360,fill=color)
        idr.rectangle((hx-12*s_,hy-2*s_,hx+12*s_,hy+8*s_),fill=color)
        idr.rounded_rectangle((hx-16*s_,hy+10*s_,hx+16*s_,hy+16*s_),radius=2*s_,fill=color)
        # the light's shine
        idr.rounded_rectangle((hx-6*s_,hy-6*s_,hx-2*s_,hy+5*s_),radius=2*s_,fill=(255,255,255,255))
        lw2=int(3.6*s_)
        for (xa,ya,xb,yb) in ((hx,hy-24*s_,hx,hy-18*s_),(hx-17*s_,hy-17*s_,hx-13*s_,hy-13*s_),(hx+17*s_,hy-17*s_,hx+13*s_,hy-13*s_),
                              (hx-23*s_,hy-3*s_,hx-18*s_,hy-3*s_),(hx+23*s_,hy-3*s_,hx+18*s_,hy-3*s_)):
            idr.line((xa,ya,xb,yb),fill=color,width=lw2)
            for (x,y) in ((xa,ya),(xb,yb)): idr.ellipse((x-lw2/2,y-lw2/2,x+lw2/2,y+lw2/2),fill=color)
        canvas.alpha_composite(ic)
    elif icon=='heart_off':
        # a heart crossed out ("don't care"), in the card colour
        s_=K; ic=Image.new('RGBA',(W,W),(0,0,0,0)); idr=ImageDraw.Draw(ic)
        import math
        hx,hy=bx,by+1*s_; k_=1.15*s_
        pts=[(hx+k_*16*math.sin(t)**3, hy-k_*(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t)))
             for t in [i*2*math.pi/240 for i in range(240)]]
        idr.polygon(pts,fill=color)
        lw2=int(4.2*s_)
        x0,y0,x1,y1=hx-17*s_,hy-18*s_,hx+17*s_,hy+16*s_
        idr.line((x0,y0,x1,y1),fill=(255,255,255,255),width=int(8*s_))
        idr.line((x0,y0,x1,y1),fill=color,width=lw2)
        for (x,y) in ((x0,y0),(x1,y1)):
            idr.ellipse((x-lw2/2,y-lw2/2,x+lw2/2,y+lw2/2),fill=color)
        canvas.alpha_composite(ic)
    elif icon=='person':
        s_=K; ic=Image.new('RGBA',(W,W),(0,0,0,0)); idr=ImageDraw.Draw(ic)
        idr.ellipse((bx-8*s_,by-17*s_,bx+8*s_,by-1*s_),fill=color)
        idr.rounded_rectangle((bx-15*s_,by+3*s_,bx+15*s_,by+22*s_),radius=10*s_,fill=color)
        # a question mark beside the head: "who?"
        qf=ImageFont.truetype(font_path,int(20*s_)); 
        if variation: qf.set_variation_by_name(variation)
        idr.text((bx+11*s_,by-24*s_),"?",font=qf,fill=color)
        ic=ic.crop((bx-br,by-br,bx+br,by+br)); m=Image.new('L',ic.size,0); ImageDraw.Draw(m).ellipse((0,0,2*br,2*br),fill=255)
        clip=Image.new('RGBA',ic.size,(0,0,0,0)); clip.paste(ic,(0,0),m)
        canvas.alpha_composite(clip,(bx-br,by-br))
    else:
        # eye with a slash (Material "visibility_off"-like), in the card colour
        s=K; ew,eh=18*s,12*s; lw=int(4.2*s)
        ex,ey=bx,by
        eye=Image.new('RGBA',(W,W),(0,0,0,0)); ed=ImageDraw.Draw(eye)
        ed.ellipse((ex-ew,ey-eh,ex+ew,ey+eh),outline=color,width=lw)
        ed.ellipse((ex-5*s,ey-5*s,ex+5*s,ey+5*s),fill=color)
        # cut a white gap along the slash, then draw the slash
        ed.line((ex-15*s,ey-15*s,ex+15*s,ey+15*s),fill=(255,255,255,255),width=int(10*s))
        ed.line((ex-15*s,ey-15*s,ex+15*s,ey+15*s),fill=color,width=lw)
        for (x,y) in ((ex-15*s,ey-15*s),(ex+15*s,ey+15*s)):
            ed.ellipse((x-lw/2,y-lw/2,x+lw/2,y+lw/2),fill=color)
        canvas.alpha_composite(eye)
    canvas.resize((256,256),Image.LANCZOS).save(out)
args=sys.argv
make(args[1], tuple(int(v) for v in args[2].split(','))+(255,), args[3], args[4], variation=(args[5] if len(args)>5 and args[5] else None), icon=(args[6] if len(args)>6 else 'eye_off'), angle=(float(args[7]) if len(args)>7 else 3.5))
