"""Reproduce the money-colour comparison; simulation is not a usability test.

Machado, Oliveira & Fernandes (2009), severity 1.0, linear RGB:
https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
CIE76 uses D65 Lab after clipping the simulated linear RGB to display gamut.
"""
import math

MATRIX = ((1.255528, -0.076749, -0.178779),
          (-0.078411, 0.930809, 0.147602),
          (0.004733, 0.691367, 0.303900))


def linear(hex_colour):
    rgb = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [v / 12.92 if v <= 0.04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]


def lab(rgb):
    xyz = [sum(a * b for a, b in zip(row, rgb)) / white
           for row, white in zip(((.4124564, .3575761, .1804375),
                                  (.2126729, .7151522, .0721750),
                                  (.0193339, .1191920, .9503041)),
                                 (.95047, 1, 1.08883))]
    x, y, z = [v ** (1 / 3) if v > (6 / 29) ** 3 else v / (3 * (6 / 29) ** 2) + 4 / 29 for v in xyz]
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


def simulated(hex_colour):
    rgb = linear(hex_colour)
    return [max(0, min(1, sum(a * b for a, b in zip(row, rgb)))) for row in MATRIX]


if __name__ == '__main__':
    owed, owe = simulated('FEBD11'), simulated('F2AB98')
    delta = math.dist(lab(owed), lab(owe))
    contrast = (sum(v * w for v, w in zip(linear('FEBD11'), (.2126, .7152, .0722))) + .05) / (linear('111111')[0] + .05)
    print(f'Marigold/salmon tritanopia CIE76 delta E: {delta:.2f}')
    print(f'Neutral ink on marigold contrast: {contrast:.2f}:1')
    print('Direction words/signs are required; colour alone is not the cue.')
