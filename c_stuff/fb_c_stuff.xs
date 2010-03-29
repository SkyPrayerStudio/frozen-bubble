/*******************************************************************************
 *
 * Copyright (c) 2001 - 2008 Guillaume Cottenceau
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2, as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 ******************************************************************************/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <iconv.h>
#include <math.h>
#include <sys/time.h>
#include <unistd.h>

#include <SDL.h>
#include <SDL_mixer.h>
#include <SDL_Pango.h>

const int XRES = 640;
const int YRES = 480;

int x, y;
int i, j;

const int Rdec = 0;
const int Gdec = 1;
const int Bdec = 2;
const int Adec = 3;

const int ANIM_SPEED = 20;
Uint32 ticks;
Uint32 to_wait;
void myLockSurface(SDL_Surface * s)
{
	while (SDL_MUSTLOCK(s) == 1 && SDL_LockSurface(s) < 0)
		SDL_Delay(10);
}
void myUnlockSurface(SDL_Surface * s)
{
	if (SDL_MUSTLOCK(s))
		SDL_UnlockSurface(s);
}
void synchro_before(SDL_Surface * s)
{
	ticks = SDL_GetTicks();	
	myLockSurface(s);
}
void synchro_after(SDL_Surface * s)
{
	myUnlockSurface(s);
	SDL_Flip(s);
	to_wait = SDL_GetTicks() - ticks;
	if (to_wait < ANIM_SPEED) {
		SDL_Delay(ANIM_SPEED - to_wait);
	}
//	else { printf("slow (%d)", ANIM_SPEED - to_wait); }
}
void fb__out_of_memory(void)
{
	fprintf(stderr, "**ERROR** Out of memory\n");
	abort();
}

int rand_(double val) { return 1+(int) (val*rand()/(RAND_MAX+1.0)); }


/************************** Graphical effects ****************************/

/*
 * Features:
 *
 *   - plasma-ordered fill (with top-bottom and/or left-right mirrored plasma's)
 *   - random points
 *   - horizontal blinds
 *   - vertical blinds
 *   - center=>edge circle
 *   - up=>down bars
 *   - top-left=>bottom-right squares
 *
 */

/* -------------- Double Store ------------------ */

void store_effect(SDL_Surface * s, SDL_Surface * img)
{
	void copy_line(int l) {
		memcpy(s->pixels + l*img->pitch, img->pixels + l*img->pitch, img->pitch);
	}
	void copy_column(int c) {
		int bpp = img->format->BytesPerPixel;
		for (y=0; y<YRES; y++)
			memcpy(s->pixels + y*img->pitch + c*bpp, img->pixels + y*img->pitch + c*bpp, bpp);
	}

	int step = 0;
	int store_thickness = 15;

	if (rand_(2) == 1) {
		while (step < YRES/2/store_thickness + store_thickness) {
			
			synchro_before(s);
			
			for (i=0; i<=YRES/2/store_thickness; i++) {
				int v = step - i;
				if (v >= 0 && v < store_thickness) {
					copy_line(i*store_thickness + v);
					copy_line(YRES - 1 - (i*store_thickness + v));
				}
			}
			step++;
			
			synchro_after(s);
		}
	}
	else {
		while (step < XRES/2/store_thickness + store_thickness) {
			
			synchro_before(s);
			
			for (i=0; i<=XRES/2/store_thickness; i++) {
				int v = step - i;
				if (v >= 0 && v < store_thickness) {
					copy_column(i*store_thickness + v);
					copy_column(XRES - 1 - (i*store_thickness + v));
				}
			}
			step++;
			
			synchro_after(s);
		}
	}
}


/* -------------- Bars ------------------ */

void bars_effect(SDL_Surface * s, SDL_Surface * img)
{
	int bpp = img->format->BytesPerPixel;
	const int bars_max_steps = 40;
	const int bars_num = 16;
	
	for (i=0; i<bars_max_steps; i++) {

		synchro_before(s);

		for (y=0; y<YRES/bars_max_steps; y++) {
			int y_  = (i*YRES/bars_max_steps + y) * img->pitch;
			int y__ = (YRES - 1 - (i*YRES/bars_max_steps + y)) * img->pitch;
			
			for (j=0; j<bars_num/2; j++) {
				int x_ =    (j*2) * (XRES/bars_num) * bpp;
				int x__ = (j*2+1) * (XRES/bars_num) * bpp;
				memcpy(s->pixels + y_ + x_,   img->pixels + y_ + x_,   (XRES/bars_num) * bpp);
				memcpy(s->pixels + y__ + x__, img->pixels + y__ + x__, (XRES/bars_num) * bpp);
			}
		}

		synchro_after(s);
	}
}


/* -------------- Squares ------------------ */

void squares_effect(SDL_Surface * s, SDL_Surface * img)
{
	int bpp = img->format->BytesPerPixel;
	const int squares_size = 32;

	int fillrect(int i, int j) {
		int c, v;
		if (i >= XRES/squares_size || j >= YRES/squares_size)
			return 0;
		v = i*squares_size*bpp + j*squares_size*img->pitch;
		for (c=0; c<squares_size; c++)
			memcpy(s->pixels + v + c*img->pitch, img->pixels + v + c*img->pitch, squares_size*bpp);
		return 1;
	}

	int still_moving = 1;

	for (i=0; still_moving; i++) {
		int k = 0;

		synchro_before(s);

		still_moving = 0;
		for (j=i; j>=0; j--) {
			if (fillrect(j, k))
				still_moving = 1;
			k++;
		}

		synchro_after(s);
	}
}


/* -------------- Circle ------------------ */

int * circle_steps;
const int circle_max_steps = 40;
void circle_init(void)
{
	int sqr(int v) { return v*v; }

	circle_steps = malloc(XRES * YRES * sizeof(int));
	if (!circle_steps)
		fb__out_of_memory();

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++) {
			int max = sqrt(sqr(XRES/2) + sqr(YRES/2));
			int value = sqrt(sqr(x-XRES/2) + sqr(y-YRES/2));
			circle_steps[x+y*XRES] = (max-value)*circle_max_steps/max;
		}
}

void circle_effect(SDL_Surface * s, SDL_Surface * img)
{
	int step = circle_max_steps;
        int bpp = img->format->BytesPerPixel;
        int in_or_out = rand_(2);

	while (step >= 0) {

		synchro_before(s);
		
		for (y=0; y<YRES; y++) {
                        void* src_line = img->pixels + y*img->pitch;
                        void* dest_line = s->pixels + y*img->pitch;
			for (x=0; x<XRES; x++) 
                                if (in_or_out == 1) {
                                        if (circle_steps[x+y*XRES] == step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                                } else {
                                        if (circle_steps[x+y*XRES] == circle_max_steps - step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                                }
                }
		step--;
				
		synchro_after(s);
	}

}


/* -------------- Plasma ------------------ */

unsigned char * plasma, * plasma2, * plasma3;
int plasma_max;
const int plasma_steps = 40;
void plasma_init(char * datapath)
{
	char * finalpath;
	char mypath[] = "/data/plasma.raw";
	FILE * f;
	finalpath = malloc(strlen(datapath) + sizeof(mypath) + 1);
	if (!finalpath)
		fb__out_of_memory();
	sprintf(finalpath, "%s%s", datapath, mypath);
	f = fopen(finalpath, "rb");
	free(finalpath);

	if (!f) {
		fprintf(stderr, "Ouch, could not open plasma.raw for reading\n");
		exit(1);
	}

	plasma = malloc(XRES * YRES);
	if (!plasma)
		fb__out_of_memory();
	if (fread(plasma, 1, XRES * YRES, f) != XRES * YRES) {
		fprintf(stderr, "Ouch, could not read %d bytes from plasma file\n", XRES * YRES);
		exit(1);
	}

        fclose(f);

	plasma_max = -1;
	for (x=0; x<XRES; x++)
		for (y=0; y<YRES; y++)
			if (plasma[x+y*XRES] > plasma_max)
				plasma_max = plasma[x+y*XRES];

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++)
			plasma[x+y*XRES] = (plasma[x+y*XRES]*plasma_steps)/(plasma_max+1);


	plasma2 = malloc(XRES * YRES);
	if (!plasma2)
		fb__out_of_memory();
	for (i=0; i<XRES*YRES; i++)
		plasma2[i] = rand_(256) - 1;

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++)
			plasma2[x+y*XRES] = (plasma2[x+y*XRES]*plasma_steps)/256;

	plasma3 = malloc(XRES * YRES);
	if (!plasma3)
		fb__out_of_memory();
}

void plasma_effect(SDL_Surface * s, SDL_Surface * img)
{
	int step = 0;
        int bpp = img->format->BytesPerPixel;
        int rnd_plasma = rand_(4);

	int plasma_type;
        if (!img->format->palette) {
                plasma_type = rand_(3);
        } else {
                plasma_type = rand_(2);
        }

        if (plasma_type == 3) {
                int int_or_out = rand_(2);
                // pixel brightness
                for (y=0; y<YRES; y++)
                        for (x=0; x<XRES; x++) {
                                Uint32 pixelvalue = 0;
                                float r, g, b;
                                memcpy(&pixelvalue, img->pixels + y*img->pitch + x*bpp, bpp);
                                r = ( (float) ( ( pixelvalue & img->format->Rmask ) >> img->format->Rshift ) ) / ( img->format->Rmask >> img->format->Rshift );
                                g = ( (float) ( ( pixelvalue & img->format->Gmask ) >> img->format->Gshift ) ) / ( img->format->Gmask >> img->format->Gshift );
                                b = ( (float) ( ( pixelvalue & img->format->Bmask ) >> img->format->Bshift ) ) / ( img->format->Bmask >> img->format->Bshift );
                                plasma3[x+y*XRES] = 255 * ( r * .299 + g * .587 + b * .114 ) * plasma_steps / 256;
                                if (int_or_out == 1)
                                        plasma3[x+y*XRES] = plasma_steps - 1 - plasma3[x+y*XRES];
                        }
        }

	while (step < plasma_steps) {

		synchro_before(s);

		if (plasma_type == 1) {
                        // with plasma file
			/* I need to un-factorize the 'plasma' call in order to let gcc optimize (tested!) */
			for (y=0; y<YRES; y++) {
                                void* src_line = img->pixels + y*img->pitch;
                                void* dest_line = s->pixels + y*img->pitch;
				if (rnd_plasma == 1) {
					for (x=0; x<XRES; x++)
						if (plasma[x+y*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else if (rnd_plasma == 2) {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+y*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else if (rnd_plasma == 3) {
					for (x=0; x<XRES; x++)
						if (plasma[x+(YRES-1-y)*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+(YRES-1-y)*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
                        }
		} else {
                        // random points or brightness
                        unsigned char* p = plasma_type == 2 ? plasma2 : plasma3;
			for (y=0; y<YRES; y++) {
                                void* src_line = img->pixels + y*img->pitch;
                                void* dest_line = s->pixels + y*img->pitch;
				for (x=0; x<XRES; x++)
					if (p[x+y*XRES] == step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                        }
		}

		step++;
				
		synchro_after(s);
	}
}


void shrink_(SDL_Surface * dest, SDL_Surface * orig, int xpos, int ypos, SDL_Rect * orig_rect, int factor)
{
	int bpp = dest->format->BytesPerPixel;
	int rx = orig_rect->x / factor;
	int rw = orig_rect->w / factor;
	int ry = orig_rect->y / factor;
	int rh = orig_rect->h / factor;
	xpos -= rx;
	ypos -= ry;
	myLockSurface(orig);
	myLockSurface(dest);
	for (x=rx; x<rx+rw; x++) {
		for (y=ry; y<ry+rh; y++) {
			if (!dest->format->palette) {
				/* there is no palette, it's cool, I can do (uber-slow) high-quality shrink */
				Uint32 pixelvalue; /* this should also be okay for 16-bit and 24-bit formats */
				int r = 0; int g = 0; int b = 0;
				for (i=0; i<factor; i++) {
					for (j=0; j<factor; j++) {
						pixelvalue = 0;
						memcpy(&pixelvalue, orig->pixels + (x*factor+i)*bpp + (y*factor+j)*orig->pitch, bpp);
						r += (pixelvalue & orig->format->Rmask) >> orig->format->Rshift;
						g += (pixelvalue & orig->format->Gmask) >> orig->format->Gshift;
						b += (pixelvalue & orig->format->Bmask) >> orig->format->Bshift;
					}
				}
				pixelvalue =
					((r/(factor*factor)) << orig->format->Rshift) +
					((g/(factor*factor)) << orig->format->Gshift) +
					((b/(factor*factor)) << orig->format->Bshift);
				memcpy(dest->pixels + (xpos+x)*bpp + (ypos+y)*dest->pitch, &pixelvalue, bpp);
			} else {
				/* there is a palette... I don't care of the bloody oldskoolers who still use
				   8-bit displays & al, they can suffer and die ;p */
				memcpy(dest->pixels + (xpos+x)*bpp + (ypos+y)*dest->pitch,
				       orig->pixels + (x*factor)*bpp + (y*factor)*orig->pitch, bpp);
			}
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void rotate_nearest_(SDL_Surface * dest, SDL_Surface * orig, double angle)
{
	int bpp = dest->format->BytesPerPixel;
        int x_, y_;
        double cosval = cos(angle);
        double sinval = sin(angle);
	if (orig->format->BytesPerPixel != dest->format->BytesPerPixel) {
                fprintf(stderr, "rotate_nearest: orig and dest surface must be of equal bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (x = 0; x < dest->w; x++) {
                for (y = 0; y < dest->h; y++) {
                        x_ = (x - dest->w/2)*cosval - (y - dest->h/2)*sinval + dest->w/2;
                        y_ = (y - dest->h/2)*cosval + (x - dest->w/2)*sinval + dest->h/2;
                        if (x_ < 0 || x_ > dest->w - 2 || y_ < 0 || y_ > dest->h - 2) {
                                *( (Uint32*) ( dest->pixels + x*bpp + y*dest->pitch ) ) = orig->format->Amask;
                                continue;
                        }
                        memcpy(dest->pixels + x*bpp + y*dest->pitch,
                               orig->pixels + x_*bpp + y_*orig->pitch, bpp);
                }
        }
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

#define CLAMP(x, low, high)  (((x) > (high)) ? (high) : (((x) < (low)) ? (low) : (x)))
#define getr(pixeladdr) ( *( ( (Uint8*) pixeladdr ) + Rdec ) )
#define getg(pixeladdr) ( *( ( (Uint8*) pixeladdr ) + Gdec ) )
#define getb(pixeladdr) ( *( ( (Uint8*) pixeladdr ) + Bdec ) )
#define geta(pixeladdr) ( *( ( (Uint8*) pixeladdr ) + Adec ) )

void rotate_bilinear_(SDL_Surface * dest, SDL_Surface * orig, double angle)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint32 *ptr;
        int x_, y_;
        int r, g, b;
        double a;
        double dx, dy;
        double cosval = cos(angle);
        double sinval = sin(angle);
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "rotate_bilinear: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "rotate_bilinear: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                double x__ = - dest->w/2*cosval - (y - dest->h/2)*sinval + dest->w/2;
                double y__ = (y - dest->h/2)*cosval - dest->w/2*sinval + dest->h/2;
                ptr = dest->pixels + y*dest->pitch;
                for (x = 0; x < dest->w; x++) {
                        Uint32 *A, *B, *C, *D;
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                *ptr = 0;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / a;
                                        g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / a;
                                        b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / a;
                                }
                                * ( ( (Uint8*) ptr ) + Rdec ) = r;  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( ( (Uint8*) ptr ) + Gdec ) = g;
                                * ( ( (Uint8*) ptr ) + Bdec ) = b;
                                * ( ( (Uint8*) ptr ) + Adec ) = a;
                        }
                        x__ += cosval;
                        y__ += sinval;
                        ptr++;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

/* assumes the surface is not totally transparent */
AV* autopseudocrop_(SDL_Surface * orig)
{
        int x_ = -1, y_ = -1, w = -1, h = -1;
        Uint8 *ptr;
        int Adec = orig->format->Ashift / 8;  // Adec is non standard from sdlpango_draw* output
        AV* ret;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "autocrop: orig surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
        y = 0;
        while (y_ == -1) {
                ptr = orig->pixels + y*orig->pitch;
                for (x = 0; x < orig->w; x++) {
                        if (*(ptr+Adec) != 0) {
                                y_ = y;
                                break;
                        }
                        ptr += 4;
                }
                y++;
        }
        y = orig->h - 1;
        while (h == -1) {
                ptr = orig->pixels + y*orig->pitch;
                for (x = 0; x < orig->w; x++) {
                        if (*(ptr+Adec) != 0) {
                                h = y - y_ + 1;
                                break;
                        }
                        ptr += 4;
                }
                y--;
        }
        x = 0;
        while (x_ == -1) {
                ptr = orig->pixels + x*4;
                for (y = 0; y < orig->h; y++) {
                        if (*(ptr+Adec) != 0) {
                                x_ = x;
                                break;
                        }
                        ptr += orig->pitch;
                }
                x++;
        }
        x = orig->w - 1;
        while (w == -1) {
                ptr = orig->pixels + x*4;
                for (y = 0; y < orig->h; y++) {
                        if (*(ptr+Adec) != 0) {
                                w = x - x_ + 1;
                                break;
                        }
                        ptr += orig->pitch;
                }
                x--;
        }
	myUnlockSurface(orig);
        ret = newAV();
        av_push(ret, newSViv(x_));
        av_push(ret, newSViv(y_));
        av_push(ret, newSViv(w));
        av_push(ret, newSViv(h));
        return ret;
}

/* access interleaved pixels */
#define CUBIC_ROW(dx, row) transform_cubic(dx, (row)[0], (row)[4], (row)[8], (row)[12])

#define CUBIC_SCALED_ROW(dx, row, arow) transform_cubic(dx, (arow)[0] * (row)[0], (arow)[4] * (row)[4], (arow)[8] * (row)[8], (arow)[12] * (row)[12])

static inline double
transform_cubic(double dx, int jm1, int j, int jp1, int jp2)
{
        // http://news.povray.org/povray.binaries.tutorials/attachment/%3CXns91B880592482seed7@povray.org%3E/Splines.bas.txt
        // Catmull-Rom yields the best results
        return ((( (     - jm1 + 3 * j - 3 * jp1 + jp2 ) * dx +
                   (   2 * jm1 - 5 * j + 4 * jp1 - jp2 ) ) * dx +
                   (     - jm1             + jp1       ) ) * dx +
                   (             2 * j                 ) ) / 2.0;
}

void rotate_bicubic_(SDL_Surface * dest, SDL_Surface * orig, double angle)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        double cosval = cos(angle);
        double sinval = sin(angle);
        double a_val, a_recip;
        int   i;
        double dx, dy;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "rotate_bicubic: orig surface must be 32bpp (bytes per pixel = %d)\n", orig->format->BytesPerPixel);
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "rotate_bicubic: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                double x__ = - dest->w/2*cosval - (y - dest->h/2)*sinval + dest->w/2 - 1;
                double y__ = (y - dest->h/2)*cosval - dest->w/2*sinval + dest->h/2 - 1;
                ptr = dest->pixels + y*dest->pitch;
                for (x = 0; x < dest->w; x++) {
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 4 || y_ < 0 || y_ > orig->h - 4) {
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                Uint8* origptr = orig->pixels + x_*Bpp + y_*orig->pitch;

                                /* the fractional error */
                                dx = x__ - x_;
                                dy = y__ - y_;
                                /* calculate alpha of result */
                                a_val = transform_cubic(dy,
                                                        CUBIC_ROW(dx, origptr + 3),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch * 2),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch * 3));
                                if (a_val <= 0.0) {
                                        a_recip = 0.0; 
                                        *(ptr+3) = 0;
                                } else if (a_val > 255.0) {
                                        a_recip = 1.0 / a_val;
                                        *(ptr+3) = 255;
                                } else { 
                                        a_recip = 1.0 / a_val;
                                        *(ptr+3) = (int) a_val;
                                }
                                /* for RGB, result = bicubic (c * alpha) / bicubic (alpha) */
                                for (i = 0; i < 3; i++) { 
                                        int newval = a_recip * transform_cubic(dy,
                                                                               CUBIC_SCALED_ROW (dx, origptr + i,                   origptr + 3),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch,     origptr + 3 + dest->pitch),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch * 2, origptr + 3 + dest->pitch * 2),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch * 3, origptr + 3 + dest->pitch * 3));
                                        *(ptr+i) = CLAMP(newval, 0, 255);
                                }
                        }
                        x__ += cosval;
                        y__ += sinval;
                        ptr += 4;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void flipflop_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int r, g, b;
        double a, dx;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "flipflop: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "flipflop: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (x = 0; x < dest->w; x++) {
                double sinval = sin((2*x+offset)/50.0)*5;
                double shading = 1.1 + cos((2*x+offset)/50.0) / 10;  // based on sinval derivative
                double x__ = x + sinval;
                int x_ = floor(x__);
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        Uint32 *A, *B;
                        if (x_ < 0 || x_ > orig->w - 2) {
                                // out of band
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                dx = x__ - x_;  // (mono)linear filtering
                                A = orig->pixels + x_*Bpp     + y*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y*orig->pitch;
                                a = geta(A) * ( 1 - dx ) + geta(B) * dx;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = getr(A) * ( 1 - dx ) + getr(B) * dx;
                                        g = getg(A) * ( 1 - dx ) + getg(B) * dx;
                                        b = getb(A) * ( 1 - dx ) + getb(B) * dx;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) / a;
                                        g = (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) / a;
                                        b = (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) / a;
                                }
                                * ( ptr + Rdec ) = CLAMP(r*shading, 0, 255);  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( ptr + Gdec ) = CLAMP(g*shading, 0, 255);
                                * ( ptr + Bdec ) = CLAMP(b*shading, 0, 255);
                                * ( ptr + Adec ) = a;
                        }
                        ptr += dest->pitch;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

float sqr(float a) { return a*a; }

void enlighten_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptrdest, *ptrorig;
        int lightx, lighty;
        double sqdistbase, sqdist, shading;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "enlighten: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "enlighten: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        lightx = dest->w/(2.5+0.3*sin((double)offset/500)) * sin((double)offset/100) + dest->w/2;
        lighty = dest->h/(2.5+0.3*cos((double)offset/500)) * cos((double)offset/100) + dest->h/2 + 10;
        for (y = 0; y < dest->h; y++) {
                ptrdest = dest->pixels + y*dest->pitch;
                ptrorig = orig->pixels + y*orig->pitch;
                sqdistbase = sqr(y - lighty) - 3;
                if (y == lighty)
                        sqdistbase -= 4;
                for (x = 0; x < dest->w; x++) {
                        sqdist = sqdistbase + sqr(x - lightx);
                        if (x == lightx)
                                sqdist -= 2;
                        shading = sqdist <= 0 ? 50 : 1 + 20/sqdist;
                        if (shading > 1.02) {
                                * ( ptrdest + Rdec ) = CLAMP(*( ptrorig + Rdec )*shading, 0, 255);
                                * ( ptrdest + Gdec ) = CLAMP(*( ptrorig + Gdec )*shading, 0, 255);
                                * ( ptrdest + Bdec ) = CLAMP(*( ptrorig + Bdec )*shading, 0, 255);
                                * ( ptrdest + Adec ) = *( ptrorig + Adec );
                        } else {
                                * ( (Uint32*) ptrdest ) = *( (Uint32*) ptrorig );
                        }
                        ptrdest += Bpp;
                        ptrorig += Bpp;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void stretch_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        int r, g, b;
        double a, dx, dy;
        double sinval = sin(offset/50.0)/10 + 1;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "stretch: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "stretch: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (x = 0; x < dest->w; x++) {
                double x__ = (x - dest->w/2) * sinval + dest->w/2;
                double cosfory = - sin(offset/50.0) * cos(M_PI*(x - dest->w/2)/dest->w) / sinval / 8 + 1;
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        Uint32 *A, *B, *C, *D;
                        double y__ = (y - dest->h/2) * cosfory + dest->h/2;
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / a;
                                        g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / a;
                                        b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / a;
                                }
                                * ( (Uint8*) ptr + Rdec ) = r;  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( (Uint8*) ptr + Gdec ) = g;
                                * ( (Uint8*) ptr + Bdec ) = b;
                                * ( (Uint8*) ptr + Adec ) = a;
                        }
                        ptr += dest->pitch;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void tilt_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        int r, g, b;
        double a, dx, dy;
        double shading;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "tilt: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "tilt: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        shading = 1 - sin(offset/40.0)/10;  // shade as if a lightsource was on the left
        for (x = 0; x < dest->w; x++) {
                double zoomfact = 1 + (x - dest->w/2) * sin(offset/40.0) / dest->w / 5;
                double x__ = (x - dest->w/2) * zoomfact + dest->w/2;
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        Uint32 *A, *B, *C, *D;
                        double y__ = (y - dest->h/2) * zoomfact + dest->h/2;
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / a;
                                        g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / a;
                                        b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / a;
                                }
                                * ( (Uint8*) ptr + Rdec ) = CLAMP(r*shading, 0, 255);  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( (Uint8*) ptr + Gdec ) = CLAMP(g*shading, 0, 255);
                                * ( (Uint8*) ptr + Bdec ) = CLAMP(b*shading, 0, 255);
                                * ( (Uint8*) ptr + Adec ) = a;
                        }
                        ptr += dest->pitch;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

struct point { double x; double y; double angle; };

#define min(a,b) ( (a) < (b) ? (a) : (b) )

void points_(SDL_Surface * dest, SDL_Surface * orig, SDL_Surface * mask)
{
	int Bpp = dest->format->BytesPerPixel;
        static struct point * points = NULL;
        int i, amount = 200;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "points: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "points: dest surface must be 32bpp\n");
                abort();
        }
	if (mask->format->BytesPerPixel != 4) {
                fprintf(stderr, "points: mask surface must be 32bpp\n");
                abort();
        }
        if (points == NULL) {
                points = malloc(sizeof(struct point) * amount);
                if (!points)
                        fb__out_of_memory();
                for (i = 0; i < amount; i++) {
                        while (1) {
                                points[i].x = rand_(dest->w/2) + dest->w/4;
                                points[i].y = rand_(dest->h/2) + dest->h/4;
                                if (* ( (Uint32*) ( mask->pixels + ((int)points[i].y)*mask->pitch + ((int)points[i].x)*mask->format->BytesPerPixel ) ) == 0xFFFFFFFF)
                                        break;
                        }
                        points[i].angle = 2 * M_PI * rand() / RAND_MAX;
                }
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                memcpy(dest->pixels + y*dest->pitch, orig->pixels + y*orig->pitch, orig->pitch);
        }
        for (i = 0; i < amount; i++) {
                double angle_distance = 0;
                
                *( (Uint32*) ( dest->pixels + ((int)points[i].y)*dest->pitch + ((int)points[i].x)*Bpp ) ) = 0xFFCCCCCC;

                points[i].x += cos(points[i].angle);
                points[i].y += sin(points[i].angle);

                if (* ( (Uint32*) ( mask->pixels + ((int)points[i].y)*mask->pitch + ((int)points[i].x)*mask->format->BytesPerPixel ) ) != 0xFFFFFFFF) {
                        // get back on track
                        points[i].x -= cos(points[i].angle);
                        points[i].y -= sin(points[i].angle);
                        while (1) {
                                angle_distance += 2 * M_PI / 100;
                                
                                points[i].x += cos(points[i].angle + angle_distance);
                                points[i].y += sin(points[i].angle + angle_distance);
                                if (* ( (Uint32*) ( mask->pixels + ((int)points[i].y)*mask->pitch + ((int)points[i].x)*mask->format->BytesPerPixel ) ) == 0xFFFFFFFF) {
                                        points[i].angle += angle_distance;
                                        break;
                                }
                                points[i].x -= cos(points[i].angle + angle_distance);
                                points[i].y -= sin(points[i].angle + angle_distance);

                                points[i].x += cos(points[i].angle - angle_distance);
                                points[i].y += sin(points[i].angle - angle_distance);
                                if (* ( (Uint32*) ( mask->pixels + ((int)points[i].y)*mask->pitch + ((int)points[i].x)*mask->format->BytesPerPixel ) ) == 0xFFFFFFFF) {
                                        points[i].angle -= angle_distance;
                                        break;
                                }
                                points[i].x -= cos(points[i].angle - angle_distance);
                                points[i].y -= sin(points[i].angle - angle_distance);
                        }
                }
        }
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void waterize_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        int r, g, b;
        double a, dx, dy;
        static double * precalc_cos = NULL, * precalc_sin = NULL;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "waterize: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "waterize: dest surface must be 32bpp\n");
                abort();
        }
        if (precalc_cos == NULL) {  // this precalc nearly suppresses the x__ and y__ processing overhead in innerloop
                int i;
                precalc_cos = malloc(200*sizeof(double));
                precalc_sin = malloc(200*sizeof(double));
                for (i = 0; i < 200; i++) {
                        precalc_cos[i] = cos(i*2*M_PI/200.0) * 2;
                        precalc_sin[i] = sin(i*2*M_PI/150.0) * 2;
                }
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (x = 0; x < dest->w; x++) {
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        Uint32 *A, *B, *C, *D;
                        double x__ = x + precalc_cos[(x + y + offset ) % 200];
                        double y__ = y + precalc_sin[(x + y + offset ) % 150];
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / a;
                                        g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / a;
                                        b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / a;
                                }
                                * ( (Uint8*) ptr + Rdec ) = r;  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( (Uint8*) ptr + Gdec ) = g;
                                * ( (Uint8*) ptr + Bdec ) = b;
                                * ( (Uint8*) ptr + Adec ) = a;
                        }
                        ptr += dest->pitch;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void brokentv_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptrdest, *ptrorig;
        double throughness, throughness_base = 0.9 + cos(offset/50.0)*0.1;
        static int pixelize = 0;
        if (pixelize == 0) {
                if (rand_(100) == 1) {
                        pixelize = 15 + 5*cos(offset);
                }
        } else {
                pixelize--;
        }
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "brokentv: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "brokentv: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                ptrdest = dest->pixels + y*dest->pitch;
                ptrorig = orig->pixels + y*orig->pitch;
                throughness = CLAMP(sin(y/(12.0+2*sin(offset/50.0))+offset/10.0+sin(offset/100.0)*5) > 0 ? throughness_base : throughness_base + cos(offset/30.0)*0.2, 0, 1);
                for (x = 0; x < dest->w; x++) {
                        if (pixelize)
                                throughness = 0.2 + rand_(100)/100.0;
                        * ( ptrdest + Rdec ) = *( ptrorig + Rdec );
                        * ( ptrdest + Gdec ) = *( ptrorig + Gdec );
                        * ( ptrdest + Bdec ) = *( ptrorig + Bdec );
                        * ( ptrdest + Adec ) = *( ptrorig + Adec ) * throughness;
                        ptrdest += Bpp;
                        ptrorig += Bpp;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

SV* utf8key_(SDL_Event * e) {
        iconv_t cd;
        char source[2];
        SV* retval = NULL;
        source[0] = e->key.keysym.unicode & 0xFF;
        source[1] = ( e->key.keysym.unicode & 0xFF00 ) >> 8;
        cd = iconv_open("UTF-8", "UTF-16LE");
        if (cd != (iconv_t) (-1)) {
                // an utf8 char is maximum 4 bytes long
                char dest[5];
                char *src = source;
                char *dst = dest;
                size_t source_len = 2;
                size_t dest_len = 4;
                bzero(dest, 5);
                if ((iconv(cd, &src, &source_len, &dst, &dest_len)) != (size_t) (-1)) {
                        *dst = 0;
                        retval = newSVpv(dest, 0);
                }
                iconv_close(cd);
        } else {
                fprintf(stderr, "**ERROR** iconv_open failed!\n");
        }
        return retval;
}

void alphaize_(SDL_Surface * surf)
{
	myLockSurface(surf);
        for (y=0; y<surf->h; y++)
                for (x=0; x<surf->w; x++) {
                        Uint32 pixelvalue = 0;
                        int a;
                        memcpy(&pixelvalue, surf->pixels + y*surf->pitch + x*surf->format->BytesPerPixel, surf->format->BytesPerPixel);
                        a = ( ( pixelvalue & surf->format->Amask ) >> surf->format->Ashift ) / 2;
                        pixelvalue = ( pixelvalue & (~ surf->format->Amask ) ) + ( a << surf->format->Ashift );
                        memcpy(surf->pixels + y*surf->pitch + x*surf->format->BytesPerPixel, &pixelvalue, surf->format->BytesPerPixel);
                }
	myUnlockSurface(surf);
}

void pixelize_(SDL_Surface * dest, SDL_Surface * orig)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptrdest, *ptrorig;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "pixelize: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "pixelize: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                ptrdest = dest->pixels + y*dest->pitch;
                ptrorig = orig->pixels + y*orig->pitch;
                for (x = 0; x < dest->w; x++) {
                        * ( ptrdest + Rdec ) = *( ptrorig + Rdec );
                        * ( ptrdest + Gdec ) = *( ptrorig + Gdec );
                        * ( ptrdest + Bdec ) = *( ptrorig + Bdec );
                        * ( ptrdest + Adec ) = *( ptrorig + Adec ) * ( 0.2 + rand_(100)/100.0 );
                        ptrdest += Bpp;
                        ptrorig += Bpp;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void blacken_(SDL_Surface * surf, int step)
{
        Uint32 pixelvalue; /* this should also be okay for 16-bit and 24-bit formats */
        int r, g, b;
        if (surf->format->palette) {
                /* there is a palette... I don't care of the bloody oldskoolers who still use
                   8-bit displays & al, they can suffer and die ;p */
                return;
        }
	myLockSurface(surf);
        for (y=(step-1)*YRES/70; y<step*YRES/70; y++) {
                bzero(surf->pixels + y*surf->pitch, surf->format->BytesPerPixel * XRES);
                bzero(surf->pixels + (YRES-1-y)*surf->pitch, surf->format->BytesPerPixel * XRES);
        }
        for (y=step*YRES/70; y<(step+8)*YRES/70 && y<YRES; y++)
                for (x=0; x<XRES; x++) {
                        memcpy(&pixelvalue, surf->pixels + y*surf->pitch + x*surf->format->BytesPerPixel, surf->format->BytesPerPixel);
                        r = ( ((pixelvalue & surf->format->Rmask) >> surf->format->Rshift))*3/4;
                        g = ( ((pixelvalue & surf->format->Gmask) >> surf->format->Gshift))*3/4;
                        b = ( ((pixelvalue & surf->format->Bmask) >> surf->format->Bshift))*3/4;
                        pixelvalue = (r << surf->format->Rshift) + (g << surf->format->Gshift) + (b << surf->format->Bshift);
                        memcpy(surf->pixels + y*surf->pitch + x*surf->format->BytesPerPixel, &pixelvalue, surf->format->BytesPerPixel);

                        memcpy(&pixelvalue, surf->pixels + (YRES-1-y)*surf->pitch + x*surf->format->BytesPerPixel, surf->format->BytesPerPixel);
                        r = ( ((pixelvalue & surf->format->Rmask) >> surf->format->Rshift))*3/4;
                        g = ( ((pixelvalue & surf->format->Gmask) >> surf->format->Gshift))*3/4;
                        b = ( ((pixelvalue & surf->format->Bmask) >> surf->format->Bshift))*3/4;
                        pixelvalue = (r << surf->format->Rshift) + (g << surf->format->Gshift) + (b << surf->format->Bshift);
                        memcpy(surf->pixels + (YRES-1-y)*surf->pitch + x*surf->format->BytesPerPixel, &pixelvalue, surf->format->BytesPerPixel);
                }
	myUnlockSurface(surf);
}

void overlook_init_(SDL_Surface * surf)
{
	int Bpp = surf->format->BytesPerPixel;
	if (surf->format->BytesPerPixel != 4) {
                fprintf(stderr, "overlook_init: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(surf);
        for (x = 0; x < surf->w; x++) {
                Uint8 *ptr = surf->pixels + x*Bpp;
                for (y = 0; y < surf->h; y++) {
                        * ( ptr + Rdec ) = 255;
                        * ( ptr + Gdec ) = 255;
                        * ( ptr + Bdec ) = 255;
                        * ( ptr + Adec ) = 0;
                        ptr += surf->pitch;
                }
        }
	myUnlockSurface(surf);
}

void overlook_(SDL_Surface * dest, SDL_Surface * orig, int step, int pivot)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        int a;
        double shading = 1 - CLAMP((double)step / 70, 0, 1);
        double x_factor = 1 - (double)step / 700;
        static double fade = 0.9;
        double dx, dy;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "overlook: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "overlook: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (x = 0; x < dest->w; x++) {
                double y_factor = 1 - ((double)step) / 150 * MIN(pivot, abs(x - pivot) + pivot/3) / pivot;
                double x__ = pivot + (x - pivot) * x_factor;
                x_ = floor(x__);
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        double y__ = dest->h/2 + (y - dest->h/2) * y_factor;
                        Uint32 *A, *B, *C, *D;
                        y_ = floor(y__);
                        
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                * ( ptr + Adec ) = * (ptr + Adec ) * fade;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                * ( ptr + Adec ) = MAX(a * shading, * (ptr + Adec ) * fade);
                        }
                        ptr += dest->pitch;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

struct flake { int x; double y; double sinpos; double sincoeff; double wideness; double y_speed; double opacity; };

// create a fake orig flake, we'll bilinear render from here to create beautifully smooth subpixel speed
//    0    0    0    0   0
//    0   50  100   50   0
//    0  100  100  100   0
//    0   50  100   50   0
//    0    0    0    0   0
static Uint32 orig_flake[] = { 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
                               0x00000000, 0x80FFFFFF, 0xFFFFFFFF, 0x80FFFFFF, 0x00000000,
                               0x00000000, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x00000000,
                               0x00000000, 0x80FFFFFF, 0xFFFFFFFF, 0x80FFFFFF, 0x00000000,
                               0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000 };
static int orig_flake_w = 4, orig_flake_h = 4, orig_flake_pitch = 5;
static int counter_for_new_flake = 1000;

void snow_(SDL_Surface * dest, SDL_Surface * orig)
{
	int Bpp = dest->format->BytesPerPixel;
        static struct flake * flakes = NULL;
        int i, amount = 200;
        double wideness = 2.0, y_speed = 0.2, moving_speed = 0.1;
        static int new_generated = 0;
        double a, fore_a, x_flake, y_flake, dx, dy;
        int r, g, b, fore_r, fore_g, fore_b, back_a, x_, y_;
        Uint8 *orig_ptr, *ptr;
	if (orig->format->BytesPerPixel != 4) {
                fprintf(stderr, "snow: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                fprintf(stderr, "snow: dest surface must be 32bpp\n");
                abort();
        }
        if (flakes == NULL) {
                flakes = malloc(sizeof(struct flake) * amount);
                if (!flakes)
                        fb__out_of_memory();
                for (i = 0; i < amount; i++) {
                        flakes[i].x = -1;
                }
        }
	myLockSurface(orig);
	myLockSurface(dest);
        for (y = 0; y < dest->h; y++) {
                memcpy(dest->pixels + y*dest->pitch, orig->pixels + y*orig->pitch, orig->pitch);
        }
        for (i = 0; i < amount; i++) {
                if (flakes[i].x == -1) {
                        if (new_generated == 0) {
                                // gen a new one
                                flakes[i].x = wideness + rand_(dest->w - 3 - wideness*2) - 1;
                                flakes[i].y = -2;
                                flakes[i].sinpos = 100.0 * rand() / RAND_MAX;
                                flakes[i].sincoeff = 0.3 + 0.7 * rand() / RAND_MAX;
                                flakes[i].y_speed = 0.1 + y_speed * rand() / RAND_MAX;
                                flakes[i].wideness = wideness/2 + wideness/2 * rand() / RAND_MAX;
                                flakes[i].opacity = 1;
                                new_generated = counter_for_new_flake;
                                if (counter_for_new_flake > 50)
                                        counter_for_new_flake -= 2;
                        } else {
                                new_generated--;
                        }
                        continue;

                }

                // render existing flakes
                x_flake = flakes[i].x + sin(flakes[i].sinpos*flakes[i].sincoeff)*flakes[i].wideness;
                y_flake = flakes[i].y;
                x_ = floor(x_flake);
                y_ = floor(y_flake);
                dx = 1 - (x_flake - x_);
                dy = 1 - (y_flake - y_);
                // collision with background?
                orig_ptr = orig->pixels + x_ * Bpp + (y_ + 1) * orig->pitch;
                if (y_ >= 0) {
                        if (geta(orig_ptr) > 191 + rand_(64)
                            && geta(orig_ptr + 3 * Bpp) > 191 + rand_(64)) {
                                flakes[i].x = -1;
                        }
                }
                for (x = 0; x < orig_flake_w; x++) {
                        ptr = dest->pixels + (x_ + x) * Bpp + MAX(0, y_) * dest->pitch;
                        orig_ptr = orig->pixels + (x_ + x) * Bpp + MAX(0, y_) * orig->pitch;
                        for (y = MAX(0, -y_); y < orig_flake_h; y++) {
                                // 1. bilinear filter orig_flake for smooth subpixel movement
                                Uint32 *A = orig_flake + x + y*orig_flake_pitch;
                                Uint32 *B = orig_flake + (x+1) + y*orig_flake_pitch;
                                Uint32 *C = orig_flake + x + (y+1)*orig_flake_pitch;
                                Uint32 *D = orig_flake + (x+1) + (y+1)*orig_flake_pitch;
                                fore_a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (fore_a == 0) {
                                        // fully transparent, nothing to do
                                        ptr += dest->pitch;
                                        orig_ptr += orig->pitch;
                                        continue;
                                }

                                if (fore_a == 255) {
                                        // fully opaque, optimized
                                        fore_r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        fore_g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        fore_b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        fore_r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / fore_a;
                                        fore_g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / fore_a;
                                        fore_b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / fore_a;
                                }

                                fore_a *= flakes[i].opacity;

                                // 2. alpha composite with existing background (other flakes, alpha border of logo)
                                back_a = geta(ptr);
                                a = fore_a + (255 - fore_a) * back_a / 255;
                                if (a == 0) {
                                        * ( (Uint32*) ptr ) = 0;
                                } else {
                                        if (back_a == 0) {
                                                r = fore_r;
                                                g = fore_g;
                                                b = fore_b;
                                        } else {
                                                r = (fore_r * fore_a + ((getr(ptr) * (255 - fore_a) * back_a) / 255)) / a;
                                                g = (fore_g * fore_a + ((getg(ptr) * (255 - fore_a) * back_a) / 255)) / a;
                                                b = (fore_b * fore_a + ((getb(ptr) * (255 - fore_a) * back_a) / 255)) / a;
                                        }
//                                        if (fore_a>255 ||fore_r>255||fore_g>255||fore_b>255||a>255||r>255||g>255||b>255){
//                                                printf("%dx%d (at %dx%d, d%fx%f):\n", x, y, x_, y_, dx, dy);
//                                                printf("\tA = %d %d %d %d\n", geta(A), getr(A), getg(A), getb(A));
//                                                printf("\tB = %d %d %d %d\n", geta(B), getr(B), getg(B), getb(B));
//                                                printf("\tC = %d %d %d %d\n", geta(C), getr(C), getg(C), getb(C));
//                                                printf("\tD = %d %d %d %d\n", geta(D), getr(D), getg(D), getb(D));
//                                                printf("\t\t=> %f %d %d %d\n", fore_a, fore_r, fore_g, fore_b);
//                                                printf("\talpha with existing %d %d %d %d\n", geta(ptr), getr(ptr), getg(ptr), getb(ptr));
//                                                printf("\t\t=> %f %d %d %d\n", a, r, g, b); }
//                                                abort();
//                                        }
                                        if (flakes[i].x == -1) {
                                                * ( orig_ptr + Rdec ) = r;
                                                * ( orig_ptr + Gdec ) = g;
                                                * ( orig_ptr + Bdec ) = b;
                                                * ( orig_ptr + Adec ) = a;
                                        }
                                        * ( ptr + Rdec ) = r;
                                        * ( ptr + Gdec ) = g;
                                        * ( ptr + Bdec ) = b;
                                        * ( ptr + Adec ) = a;
                                }
                                ptr += dest->pitch;
                                orig_ptr += orig->pitch;
                        }
                }
                flakes[i].sinpos += moving_speed;
                flakes[i].y += flakes[i].y_speed;
                if (flakes[i].y > dest->h - 22)
                        flakes[i].opacity = (double)(dest->h - flakes[i].y - 2)/20;
                if (flakes[i].y >= dest->h - 4)
                        flakes[i].x = -1;
        }
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void draw_line_(SDL_Surface* surface, int x1, int y1, int x2, int y2, SDL_Color* color)
{
        // simple Bresenham line drawing. should be antialiased for better output, but is not.
        int bpp = surface->format->BytesPerPixel;
        Uint8* p;
        int pix = SDL_MapRGB(surface->format, color->r, color->g, color->b);
        double xacc, yacc, x, y;
	myLockSurface(surface);
        if (abs(x2 - x1) > abs(y2 - y1)) {
                xacc = x2 > x1 ? 1 : -1;
                yacc = xacc * (y2 - y1) / (x2 - x1);
        } else {
                yacc = y2 > y1 ? 1 : -1;
                xacc = yacc * (x2 - x1) / (y2 - y1);
        }
        x = x1;
        y = y1;
        while (1) {
                x += xacc;
                y += yacc;
                if ((xacc == 1 && x > x2)
                    || (xacc == -1 && x < x2)
                    || (yacc == 1 && y > y2)
                    || (yacc == -1 && y < y2)) {
                        myUnlockSurface(surface);
                        return;
                }
                p = (Uint8*)surface->pixels + bpp*(int)x + surface->pitch*(int)y;
                switch(bpp) {
                case 1:
                        *(Uint8*)p = pix;
                        break;
                case 2:
                        *(Uint16*)p = pix;
                        break;
                case 3:
                        if (SDL_BYTEORDER == SDL_BIG_ENDIAN) {
                                p[0] = (pix >> 16) & 0xff;
                                p[1] = (pix >> 8) & 0xff;
                                p[2] = pix & 0xff;
                        } else {
                                p[0] = pix & 0xff;
                                p[1] = (pix >> 8) & 0xff;
                                p[2] = (pix >> 16) & 0xff;
                        }
                        break;
                case 4:
                        *(Uint32*)p = pix;
                        break;
                }
        }
}

SDL_Surface* sdlpango_draw_(SDLPango_Context* context, char* text, int width, char* align)
{
        SDLPango_Alignment alignment = !strcmp(align, "left") ? SDLPANGO_ALIGN_LEFT :
                                       !strcmp(align, "center") ? SDLPANGO_ALIGN_CENTER : SDLPANGO_ALIGN_RIGHT;
        SDLPango_SetMinimumSize(context, width, 0);
        SDLPango_SetText_GivenAlignment(context, text, -1, alignment);
	return SDLPango_CreateSurfaceDraw(context);
}


/************************** Gateway to Perl ****************************/

MODULE = fb_c_stuff		PACKAGE = fb_c_stuff

void
init_effects(datapath)
     char * datapath
	CODE:
		circle_init();
		plasma_init(datapath);
		srand(time(NULL));

void
effect(s, img)
     SDL_Surface * s
     SDL_Surface * img
	CODE:
		int randvalue = rand_(8);
		if (randvalue == 1 || randvalue == 2)
			store_effect(s, img);
		else if (randvalue == 3 || randvalue == 4 || randvalue == 5)
			plasma_effect(s, img);
                else if (randvalue == 6)
			circle_effect(s, img);
		else if (randvalue == 7)
			bars_effect(s, img);
		else
                        squares_effect(s, img);

int
get_synchro_value()
	CODE:
		RETVAL = Mix_GetSynchroValue();
	OUTPUT:
		RETVAL

void
set_music_position(pos)
	double pos
	CODE:
		Mix_SetMusicPosition(pos);

int
fade_in_music_position(music, loops, ms, pos)
	Mix_Music *music
	int loops
	int ms
	int pos
	CODE:
		RETVAL = Mix_FadeInMusicPos(music, loops, ms, pos);
	OUTPUT:
		RETVAL

void
shrink(dest, orig, xpos, ypos, orig_rect, factor)
        SDL_Surface * dest
        SDL_Surface * orig
        int xpos
	int ypos
        SDL_Rect * orig_rect
        int factor
	CODE:
		shrink_(dest, orig, xpos, ypos, orig_rect, factor);

void
rotate_nearest(dest, orig, angle)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
	CODE:
		rotate_nearest_(dest, orig, angle);

void
rotate_bilinear(dest, orig, angle)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
	CODE:
		rotate_bilinear_(dest, orig, angle);

AV*
autopseudocrop(orig)
        SDL_Surface * orig
	CODE:
		RETVAL = autopseudocrop_(orig);
	OUTPUT:
		RETVAL

void
rotate_bicubic(dest, orig, angle)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
	CODE:
		rotate_bicubic_(dest, orig, angle);

void
flipflop(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		flipflop_(dest, orig, offset);

void
enlighten(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		enlighten_(dest, orig, offset);

void
stretch(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		stretch_(dest, orig, offset);

void
tilt(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		tilt_(dest, orig, offset);

void
points(dest, orig, mask)
        SDL_Surface * dest
        SDL_Surface * orig
        SDL_Surface * mask
	CODE:
		points_(dest, orig, mask);

void
waterize(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		waterize_(dest, orig, offset);

void
brokentv(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		brokentv_(dest, orig, offset);

void
alphaize(surf)
        SDL_Surface * surf
	CODE:
                alphaize_(surf);

void
pixelize(dest, orig)
        SDL_Surface * dest
        SDL_Surface * orig
	CODE:
		pixelize_(dest, orig);

void
blacken(surf, step)
        SDL_Surface * surf
        int step
	CODE:
		blacken_(surf, step);

void
overlook_init(surf)
        SDL_Surface * surf
	CODE:
		overlook_init_(surf);

void
overlook(dest, orig, step, pivot)
        SDL_Surface * dest
        SDL_Surface * orig
        int step
        int pivot
	CODE:
                overlook_(dest, orig, step, pivot);

void
snow(dest, orig)
        SDL_Surface * dest
        SDL_Surface * orig
	CODE:
		snow_(dest, orig);

void
draw_line(SDL_Surface* surface, int x1, int y1, int x2, int y2, SDL_Color* color)
        CODE:
                draw_line_(surface, x1, y1, x2, y2, color);

void
_exit(status)
        int status

void
fbdelay(ms)
        int ms
	CODE:
                     /* Beuh, SDL::App::delay is bugged, sometimes it doesn't sleep, must be related to signals
			or something... but doing the do/while in Perl seems to slow down the game too much on
			some machines, so I'll do it from here */
		     int then;
		     do {
			 then = SDL_GetTicks();
			 SDL_Delay(ms);
			 ms -= SDL_GetTicks() - then;
		     } while (ms > 1);
		     
SV *
utf8key(event)
  SDL_Event * event
  CODE:
  RETVAL = utf8key_(event);
  OUTPUT:
  RETVAL


Sint16
JoyAxisEventValue ( e )
        SDL_Event *e
        CODE:
                RETVAL = e->jaxis.value;   // buggy up to 2.1.2
        OUTPUT: 
                RETVAL

Uint8
JOYAXISMOTION ()
        CODE:
                RETVAL = SDL_JOYAXISMOTION; // missing in 2.1.2
        OUTPUT:
                RETVAL

Uint8
JOYBUTTONDOWN ()
        CODE:
                RETVAL = SDL_JOYBUTTONDOWN; // missing in 2.1.2
        OUTPUT:
                RETVAL

Uint8
JOYBUTTONUP ()
        CODE:
                RETVAL = SDL_JOYBUTTONUP; // missing in 2.1.2
        OUTPUT:
                RETVAL

SDL_Surface*
sdlpango_draw(SDLPango_Context* context, char* text, int width)
	PREINIT:
		char* CLASS = "SDL::Surface";
        CODE:
                RETVAL = sdlpango_draw_(context, text, width, "left");
        OUTPUT:
                RETVAL

SDL_Surface*
sdlpango_draw_givenalignment(SDLPango_Context* context, char* text, int width, char* alignment)
	PREINIT:
		char* CLASS = "SDL::Surface";
        CODE:
                RETVAL = sdlpango_draw_(context, text, width, alignment);
        OUTPUT:
                RETVAL
